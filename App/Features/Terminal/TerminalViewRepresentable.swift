import SwiftUI

struct TerminalViewRepresentable: UIViewControllerRepresentable {
    let sshSession: SSHSession
    @Binding var terminalTitle: String
    @ObservedObject var appearanceViewModel: AppearanceViewModel
    var onTerminalReady: ((TerminalViewController) -> Void)?

    func makeUIViewController(context: Context) -> TerminalViewController {
        let dataSource = SSHTerminalDataSource(sshSession: sshSession)
        let viewController = TerminalViewController(dataSource: dataSource)
        viewController.onTitleChange = { title in
            terminalTitle = title
        }
        context.coordinator.viewController = viewController
        return viewController
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {
        uiViewController.applyAppearance(appearanceViewModel.appearance)
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
