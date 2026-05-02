import Combine
import UIKit

@MainActor
final class IdleTimerController {
    private let sessionManager: SSHSessionManager
    private let appearanceViewModel: AppearanceViewModel
    private var cancellables = Set<AnyCancellable>()

    init(sessionManager: SSHSessionManager, appearanceViewModel: AppearanceViewModel) {
        self.sessionManager = sessionManager
        self.appearanceViewModel = appearanceViewModel

        sessionManager.$state
            .combineLatest(appearanceViewModel.$appearance)
            .sink { [weak self] state, appearance in
                self?.apply(state: state, appearance: appearance)
            }
            .store(in: &cancellables)
    }

    private func apply(state: SessionManagerState, appearance: TerminalAppearance) {
        let shouldDisableIdle: Bool
        if appearance.preventDeviceSleepWhileConnected, case .active = state {
            shouldDisableIdle = true
        } else {
            shouldDisableIdle = false
        }
        if UIApplication.shared.isIdleTimerDisabled != shouldDisableIdle {
            UIApplication.shared.isIdleTimerDisabled = shouldDisableIdle
        }
    }
}
