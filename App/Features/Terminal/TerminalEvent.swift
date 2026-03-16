import Foundation

enum TerminalEvent: Sendable {
    case bell
    case directoryChanged(String)
    case titleChanged(String)
    case commandFinished(exitCode: Int?)
    case commandStarted
    case promptReady
    case notification(title: String, body: String)
}
