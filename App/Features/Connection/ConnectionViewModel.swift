import Foundation
import Network
import os

enum ConnectionViewModelError: Error, Equatable {
    case emptyHost
    case emptyUsername
    case invalidPort
    case invalidHostFormat
    case invalidUsernameFormat
    case hostTooLong
    case usernameTooLong
    case profileNotFound
    case hostUnreachable(String)
}

@MainActor
final class ConnectionViewModel: ObservableObject, Sendable {
    @Published var profiles: [SSHConnectionProfile] = []
    @Published var availableKeys: [SSHIdentity] = []
    @Published var isTestingConnection: Bool = false
    @Published var testConnectionResult: Result<Bool, Error>?

    private let profileStore: ProfileStore
    let keyManager: KeyManager

    init(profileStore: ProfileStore, keyManager: KeyManager) {
        self.profileStore = profileStore
        self.keyManager = keyManager
    }

    func loadProfiles() async {
        let allProfiles = await profileStore.allProfiles()
        profiles = allProfiles.sorted { lhs, rhs in
            switch (lhs.lastConnected, rhs.lastConnected) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.host < rhs.host
            }
        }
    }

    func loadKeys() async {
        availableKeys = await keyManager.listAllKeys()
    }

    func addProfile(
        host: String,
        port: UInt16,
        username: String,
        authMethod: SSHAuthMethod,
        password: String?,
        autoReconnect: Bool,
        keepaliveInterval: TimeInterval = 60
    ) async throws {
        try validateFields(host: host, username: username, port: port)

        let profile = SSHConnectionProfile(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: authMethod,
            autoReconnect: autoReconnect,
            keepaliveInterval: keepaliveInterval
        )
        try await profileStore.addProfile(profile, password: password)
        await loadProfiles()
    }

    func updateProfile(
        _ profile: SSHConnectionProfile,
        password: String?
    ) async throws {
        try validateFields(host: profile.host, username: profile.username, port: profile.port)
        try await profileStore.updateProfile(profile, password: password)
        await loadProfiles()
    }

    func deleteProfile(id: UUID) async throws {
        try await profileStore.deleteProfile(id: id)
        await loadProfiles()
    }

    func markConnected(id: UUID) async throws {
        guard var profile = await profileStore.profile(id: id) else {
            throw ConnectionViewModelError.profileNotFound
        }
        profile.lastConnected = Date()
        try await profileStore.updateProfile(profile)
        await loadProfiles()
    }

    func testConnection(host: String, port: UInt16) async {
        isTestingConnection = true
        testConnectionResult = nil

        let result: Result<Bool, Error> = await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .failure(
                    ConnectionViewModelError.invalidPort
                ))
                return
            }
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )

            let queue = DispatchQueue(label: "com.divinemarssh.connectiontest")
            let resumed = LockedFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    if resumed.setIfUnset() {
                        continuation.resume(returning: .success(true))
                    }
                case .failed(let error):
                    connection.cancel()
                    if resumed.setIfUnset() {
                        continuation.resume(returning: .failure(
                            ConnectionViewModelError.hostUnreachable(error.localizedDescription)
                        ))
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 5) {
                connection.cancel()
                if resumed.setIfUnset() {
                    continuation.resume(returning: .failure(
                        ConnectionViewModelError.hostUnreachable("Connection timed out")
                    ))
                }
            }
        }

        testConnectionResult = result
        isTestingConnection = false
    }

    func password(for profileID: UUID) async -> String? {
        await profileStore.password(for: profileID)
    }

    // MARK: - Validation

    nonisolated func validateFields(host: String, username: String, port: UInt16) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedHost.isEmpty {
            throw ConnectionViewModelError.emptyHost
        }
        if trimmedUsername.isEmpty {
            throw ConnectionViewModelError.emptyUsername
        }
        if port == 0 {
            throw ConnectionViewModelError.invalidPort
        }
        if trimmedHost.count > 253 {
            throw ConnectionViewModelError.hostTooLong
        }
        if trimmedUsername.count > 128 {
            throw ConnectionViewModelError.usernameTooLong
        }
        if trimmedHost.contains(where: { $0.asciiValue.map { $0 < 32 } ?? false }) {
            throw ConnectionViewModelError.invalidHostFormat
        }
        let validHostPattern = #"^[a-zA-Z0-9.\-:\[\]]+$"#
        if trimmedHost.range(of: validHostPattern, options: .regularExpression) == nil {
            throw ConnectionViewModelError.invalidHostFormat
        }
        if trimmedUsername.contains(where: { $0.asciiValue.map { $0 < 32 } ?? false }) {
            throw ConnectionViewModelError.invalidUsernameFormat
        }
        let validUsernamePattern = #"^[a-zA-Z0-9._\-@]+$"#
        if trimmedUsername.range(of: validUsernamePattern, options: .regularExpression) == nil {
            throw ConnectionViewModelError.invalidUsernameFormat
        }
    }
}

private final class LockedFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    func setIfUnset() -> Bool {
        lock.withLock { flag in
            if flag { return false }
            flag = true
            return true
        }
    }
}
