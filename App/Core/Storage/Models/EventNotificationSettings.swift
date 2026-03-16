import Foundation

struct EventNotificationConfig: Codable, Sendable, Equatable {
    var haptic: Bool
    var sound: Bool
    var flash: Bool
    var pushNotification: Bool

    static let off = EventNotificationConfig(haptic: false, sound: false, flash: false, pushNotification: false)
}

struct EventNotificationSettings: Codable, Sendable, Equatable {
    var bell: EventNotificationConfig
    var commandFinished: EventNotificationConfig
    var shellNotification: EventNotificationConfig

    init() {
        bell = EventNotificationConfig(haptic: true, sound: false, flash: false, pushNotification: false)
        commandFinished = EventNotificationConfig(haptic: false, sound: false, flash: true, pushNotification: true)
        shellNotification = EventNotificationConfig(haptic: false, sound: false, flash: false, pushNotification: true)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EventNotificationSettings()
        bell = try container.decodeIfPresent(EventNotificationConfig.self, forKey: .bell) ?? defaults.bell
        commandFinished = try container.decodeIfPresent(EventNotificationConfig.self, forKey: .commandFinished) ?? defaults.commandFinished
        shellNotification = try container.decodeIfPresent(EventNotificationConfig.self, forKey: .shellNotification) ?? defaults.shellNotification
    }
}
