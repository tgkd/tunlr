import SwiftUI
@preconcurrency import AVFoundation

struct QRFingerprintScanner: View {
    let knownHostsStore: KnownHostsStore
    @Environment(\.dismiss) private var dismiss
    @State private var scanResult: ScanResult?
    @State private var errorMessage: String?
    @State private var isTorchOn = false

    enum ScanResult: Equatable {
        case success(ParsedFingerprint)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview(onCodeScanned: handleScannedCode, isTorchOn: $isTorchOn)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let result = scanResult {
                        resultOverlay(for: result)
                            .padding()
                    } else {
                        instructionOverlay
                            .padding()
                    }
                }
            }
            .navigationTitle("Scan Host Fingerprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isTorchOn.toggle()
                    } label: {
                        Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var instructionOverlay: some View {
        VStack(spacing: 8) {
            Text("Point camera at QR code")
                .font(.headline)
            Text("Scan an ssh-trust:// QR code to pre-trust a host fingerprint")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func resultOverlay(for result: ScanResult) -> some View {
        switch result {
        case .success(let parsed):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Fingerprint Trusted")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host: \(parsed.hostname):\(parsed.port)")
                    Text("Type: \(parsed.keyType)")
                    Text(parsed.fingerprint)
                        .font(.caption.monospaced())
                }
                .font(.subheadline)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "xmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Invalid QR Code")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)

                Button("Scan Again") {
                    scanResult = nil
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func handleScannedCode(_ code: String) {
        guard scanResult == nil else { return }

        do {
            let parsed = try FingerprintURIParser.parse(code)
            let hostKey = SSHHostKey(
                hostname: parsed.hostname,
                port: parsed.port,
                keyType: parsed.keyType,
                publicKeyData: Data(),
                fingerprint: parsed.fingerprint,
                firstSeenDate: Date()
            )
            Task {
                do {
                    try await knownHostsStore.trust(hostKey: hostKey)
                    await MainActor.run {
                        scanResult = .success(parsed)
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save fingerprint: \(error.localizedDescription)"
                    }
                }
            }
        } catch let error as FingerprintURIParserError {
            scanResult = .error(describeError(error))
        } catch {
            scanResult = .error("Unexpected error: \(error.localizedDescription)")
        }
    }

    private func describeError(_ error: FingerprintURIParserError) -> String {
        switch error {
        case .invalidScheme: return "Not an ssh-trust:// URI"
        case .missingHost: return "Missing hostname"
        case .invalidPort: return "Invalid port number"
        case .missingFingerprint: return "Missing fingerprint parameter"
        case .invalidFingerprintFormat: return "Invalid fingerprint format (expected SHA256:...)"
        case .missingKeyType: return "Missing key type parameter"
        case .unsupportedKeyType(let t): return "Unsupported key type: \(t)"
        }
    }
}

// MARK: - Camera Preview

private struct CameraPreview: UIViewControllerRepresentable {
    let onCodeScanned: @MainActor (String) -> Void
    @Binding var isTorchOn: Bool

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.setTorch(on: isTorchOn)
    }
}

private final class CameraViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: (@MainActor (String) -> Void)?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let session = captureSession
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        onCodeScanned?(value)
    }
}
