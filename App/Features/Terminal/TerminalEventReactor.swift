import UIKit
import AudioToolbox
import UserNotifications

enum FlashStyle: Sendable {
    case bell
    case success
    case failure
}

@MainActor
final class TerminalEventReactor {
    private let appearanceViewModel: AppearanceViewModel
    private let hapticGenerator = UINotificationFeedbackGenerator()
    private var lastBellDate: Date?
    private var commandIsRunning = false
    private var terminalTitle: String = ""

    var onFlash: ((FlashStyle) -> Void)?

    init(appearanceViewModel: AppearanceViewModel) {
        self.appearanceViewModel = appearanceViewModel
        hapticGenerator.prepare()
    }

    func updateTitle(_ title: String) {
        terminalTitle = title
    }

    func handle(_ event: TerminalEvent) {
        let settings = appearanceViewModel.appearance.eventNotifications

        switch event {
        case .bell:
            guard shouldAllowBell() else { return }
            fire(config: settings.bell, title: "Bell", body: terminalTitle.isEmpty ? "Terminal bell" : terminalTitle, feedbackType: .warning, flashStyle: .bell)

        case .commandStarted:
            commandIsRunning = true

        case .commandFinished(let exitCode):
            guard commandIsRunning else { return }
            commandIsRunning = false
            let success = exitCode == nil || exitCode == 0
            let body = success ? "Command completed successfully" : "Command failed (exit \(exitCode ?? -1))"
            fire(config: settings.commandFinished, title: "Command Finished", body: body, feedbackType: success ? .success : .error, flashStyle: success ? .success : .failure)

        case .notification(let title, let body):
            fire(config: settings.shellNotification, title: title, body: body, feedbackType: .success, flashStyle: .success)

        case .promptReady, .directoryChanged, .titleChanged:
            break
        }
    }

    private func shouldAllowBell() -> Bool {
        let now = Date()
        if let last = lastBellDate, now.timeIntervalSince(last) < 0.5 {
            return false
        }
        lastBellDate = now
        return true
    }

    private func fire(config: EventNotificationConfig, title: String, body: String, feedbackType: UINotificationFeedbackGenerator.FeedbackType, flashStyle: FlashStyle) {
        if config.haptic {
            hapticGenerator.notificationOccurred(feedbackType)
            hapticGenerator.prepare()
        }
        if config.sound {
            AudioServicesPlaySystemSound(1007)
        }
        if config.flash {
            onFlash?(flashStyle)
        }
        if config.pushNotification {
            scheduleLocalNotification(title: title, body: body)
        }
    }

    private func scheduleLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }
}
