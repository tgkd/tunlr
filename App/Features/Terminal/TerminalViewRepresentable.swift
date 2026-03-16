import SwiftUI

struct TerminalViewRepresentable: UIViewControllerRepresentable {
    let sshSession: SSHSession
    @Binding var terminalTitle: String
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    var voiceInputEnabled: Bool = false
    var onTerminalReady: ((TerminalViewController) -> Void)?
    var onMicrophoneTapped: (() -> Void)?
    var onTerminalEvent: ((TerminalEvent) -> Void)?

    func makeUIViewController(context: Context) -> TerminalViewController {
        let dataSource = SSHTerminalDataSource(sshSession: sshSession)
        let viewController = TerminalViewController(dataSource: dataSource)
        viewController.onTitleChange = { title in
            terminalTitle = title
        }
        viewController.onMicrophoneTapped = onMicrophoneTapped
        viewController.onTerminalEvent = onTerminalEvent
        viewController.voiceInputEnabled = voiceInputEnabled
        context.coordinator.viewController = viewController
        return viewController
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {
        uiViewController.applyAppearance(appearanceViewModel.appearance)
        uiViewController.voiceInputEnabled = voiceInputEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator {
        let parent: TerminalViewRepresentable
        weak var viewController: TerminalViewController? {
            didSet {
                if let viewController {
                    parent.onTerminalReady?(viewController)
                }
            }
        }

        init(_ parent: TerminalViewRepresentable) {
            self.parent = parent
        }
    }
}
