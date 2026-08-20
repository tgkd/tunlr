@preconcurrency import AVFoundation
import WhisperKit

enum WhisperModelSize: String, CaseIterable, Sendable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        }
    }

    var subtitle: String {
        switch self {
        case .tiny: return "Fastest, ~40 MB"
        case .base: return "Balanced, ~75 MB"
        case .small: return "Most accurate, ~250 MB"
        }
    }

    static var stored: WhisperModelSize {
        let raw = UserDefaults.standard.string(forKey: "whisperModelSize") ?? WhisperModelSize.tiny.rawValue
        return WhisperModelSize(rawValue: raw) ?? .tiny
    }
}

enum WhisperServiceState: Sendable, Equatable {
    case idle
    case downloading
    case recording
    case transcribing
    case noSpeech
    case permissionDenied
    case error(String)
}

enum WhisperTranscriptionResult: Sendable {
    case transcription(String)
    case noSpeech
    case error(String)
}

final class AudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Float = 0

    var value: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

actor WhisperService {
    private let levelBox = AudioLevelBox()

    nonisolated var currentLevel: Float { levelBox.value }

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var audioFilePath: URL?
    private var audioFile: AVAudioFile?

    private(set) var state: WhisperServiceState = .idle

    private var loadedModelSize: WhisperModelSize?

    var isModelReady: Bool { whisperKit != nil }

    nonisolated func isModelCached(for size: WhisperModelSize? = nil) -> Bool {
        let modelSize = size ?? .stored
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let modelsDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard fm.fileExists(atPath: modelsDir.path()) else { return false }
        let contents = (try? fm.contentsOfDirectory(atPath: modelsDir.path())) ?? []
        return contents.contains { $0.contains(modelSize.rawValue.replacingOccurrences(of: "openai_whisper-", with: "")) }
    }

    nonisolated func deleteModel(for size: WhisperModelSize) -> Bool {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let modelsDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard let contents = try? fm.contentsOfDirectory(atPath: modelsDir.path()) else { return false }
        let keyword = size.rawValue.replacingOccurrences(of: "openai_whisper-", with: "")
        var deleted = false
        for item in contents where item.contains(keyword) {
            let itemPath = modelsDir.appendingPathComponent(item)
            try? fm.removeItem(at: itemPath)
            deleted = true
        }
        return deleted
    }

    enum MicPermission: Sendable {
        case undetermined, granted, denied
    }

    nonisolated func checkMicrophonePermission() -> MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .undetermined
        case .granted: return .granted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    nonisolated func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func ensureModelReady() async throws {
        let desired = WhisperModelSize.stored
        if whisperKit != nil, loadedModelSize == desired { return }

        whisperKit = nil
        loadedModelSize = nil
        state = .downloading
        let kit = try await WhisperKit(model: desired.rawValue)
        whisperKit = kit
        loadedModelSize = desired
        state = .idle
    }

    func startRecording() async throws {
        guard state == .idle else { return }

        try await ensureModelReady()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent("whisper_recording.wav")
        try? FileManager.default.removeItem(at: filePath)

        let wavFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let file = try AVAudioFile(forWriting: filePath, settings: wavFormat.settings)

        let converter = AVAudioConverter(from: recordingFormat, to: wavFormat)
        let sampleRateRatio = 16000.0 / recordingFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [wavFormat, levelBox] buffer, _ in
            if let samples = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sumOfSquares: Float = 0
                for index in 0..<count {
                    sumOfSquares += samples[index] * samples[index]
                }
                let rms = count > 0 ? (sumOfSquares / Float(count)).squareRoot() : 0
                levelBox.value = min(1, rms * 6)
            }
            guard let converter else { return }
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * sampleRateRatio
            )
            guard frameCount > 0 else { return }
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: wavFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .haveData {
                try? file.write(from: convertedBuffer)
            }
        }

        try engine.start()

        self.audioEngine = engine
        self.audioFilePath = filePath
        self.audioFile = file
        state = .recording
    }

    func stopAndTranscribe() async -> WhisperTranscriptionResult {
        guard state == .recording else {
            return .error("Not recording")
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        levelBox.value = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        state = .transcribing

        guard let filePath = audioFilePath else {
            state = .idle
            return .error("No audio recorded")
        }

        guard let whisperKit else {
            state = .idle
            return .error("Model not loaded")
        }

        do {
            let audioPath = filePath.path()
            let results = try await whisperKit.transcribe(audioPath: audioPath)
            let joined = results.map { $0.text }.joined(separator: " ")
            let text = Self.strippingNonSpeechMarkers(joined)
            state = .idle

            if text.isEmpty {
                return .noSpeech
            }
            return .transcription(text)
        } catch {
            state = .error(error.localizedDescription)
            return .error(error.localizedDescription)
        }
    }

    static func strippingNonSpeechMarkers(_ raw: String) -> String {
        let pattern = "\\[\\s*(BLANK_AUDIO|SILENCE|INAUDIBLE|MUSIC|NOISE|SOUND|APPLAUSE|LAUGHTER)\\s*\\]"
        let stripped = raw.replacingOccurrences(
            of: pattern,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        levelBox.value = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let path = audioFilePath {
            try? FileManager.default.removeItem(at: path)
        }
        audioFilePath = nil
        state = .idle
    }
}
