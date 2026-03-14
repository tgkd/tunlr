import Foundation

struct SSHConnectionProfile: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var host: String
    var port: UInt16
    var username: String
    var authMethod: SSHAuthMethod
    var lastConnected: Date?
    var autoReconnect: Bool

    init(
        id: UUID = UUID(),
        host: String,
        port: UInt16 = 22,
        username: String,
        authMethod: SSHAuthMethod,
        lastConnected: Date? = nil,
        autoReconnect: Bool = false
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.lastConnected = lastConnected
        self.autoReconnect = autoReconnect
    }
}
