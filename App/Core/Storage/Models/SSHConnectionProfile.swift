import Foundation

struct SSHConnectionProfile: Codable, Sendable, Identifiable, Equatable {
    static let minimumKeepaliveInterval: TimeInterval = 1
    static let maximumKeepaliveInterval: TimeInterval = 86_400

    let id: UUID
    var host: String
    var port: UInt16
    var username: String
    var authMethod: SSHAuthMethod
    var lastConnected: Date?
    var autoReconnect: Bool
    var keepaliveInterval: TimeInterval

    init(
        id: UUID = UUID(),
        host: String,
        port: UInt16 = 22,
        username: String,
        authMethod: SSHAuthMethod,
        lastConnected: Date? = nil,
        autoReconnect: Bool = false,
        keepaliveInterval: TimeInterval = 60
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.lastConnected = lastConnected
        self.autoReconnect = autoReconnect
        self.keepaliveInterval = keepaliveInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(UInt16.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        authMethod = try container.decode(SSHAuthMethod.self, forKey: .authMethod)
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? false
        keepaliveInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .keepaliveInterval) ?? 60
    }
}
