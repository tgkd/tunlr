@preconcurrency import AVFoundation
import WhisperKit

enum WhisperServiceState: Sendable, Equatable {
    case idle
    case downloading
    case recording
    case transcribing
    case error(String)
}

enum WhisperTranscriptionResult: Sendable {
    case transcription(String)
    case error(String)
}

actor WhisperService {
    private nonisolated(unsafe) var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var audioFilePath: URL?
    private var audioFile: AVAudioFile?

    private(set) var state: WhisperServiceState = .idle

    private let modelVariant = "openai_whisper-tiny"

    var isModelReady: Bool { whisperKit != nil }

    nonisolated func isModelCached() -> Bool {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let modelsDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard fm.fileExists(atPath: modelsDir.path()) else { return false }
        let contents = (try? fm.contentsOfDirectory(atPath: modelsDir.path())) ?? []
        return !contents.isEmpty
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
        do {
            return try await AVAudioApplication.requestRecordPermission()
        } catch {
            return false
        }
    }

    func ensureModelReady() async throws {
        guard whisperKit == nil else { return }
        state = .downloading
        let kit = try await WhisperKit(model: modelVariant)
        whisperKit = kit
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
            [wavFormat] buffer, _ in
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
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            state = .idle

            if text.isEmpty {
                return .error("No speech detected")
            }
            return .transcription(text)
        } catch {
            state = .error(error.localizedDescription)
            return .error(error.localizedDescription)
        }
    }

    func cancel() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let path = audioFilePath {
            try? FileManager.default.removeItem(at: path)
        }
        audioFilePath = nil
        state = .idle
    }
}
