import Foundation
import LocalAuthentication

struct BiometricPolicy: Sendable {
    let reuseDuration: TimeInterval
    let allowPasscodeFallback: Bool

    init(reuseDuration: TimeInterval = 60, allowPasscodeFallback: Bool = true) {
        self.reuseDuration = reuseDuration
        self.allowPasscodeFallback = allowPasscodeFallback
    }

    func createContext() -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration
        if !allowPasscodeFallback {
            context.localizedFallbackTitle = ""
        }
        return context
    }

    enum BiometricError: Error, Equatable {
        case biometryNotAvailable
        case biometryLockout
        case userCancelled
        case authenticationFailed
        case systemError(Int)
    }

    static func mapError(_ error: Error) -> BiometricError {
        guard let laError = error as? LAError else {
            return .systemError((error as NSError).code)
        }
        switch laError.code {
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .biometryNotAvailable
        case .biometryLockout:
            return .biometryLockout
        case .userCancel:
            return .userCancelled
        case .authenticationFailed:
            return .authenticationFailed
        default:
            return .systemError(laError.code.rawValue)
        }
    }
}
