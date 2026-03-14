import Foundation

struct ParsedFingerprint: Sendable, Equatable {
    let hostname: String
    let port: UInt16
    let fingerprint: String
    let keyType: String
}

enum FingerprintURIParserError: Error, Equatable {
    case invalidScheme
    case missingHost
    case invalidPort
    case missingFingerprint
    case invalidFingerprintFormat
    case missingKeyType
    case unsupportedKeyType(String)
}

struct FingerprintURIParser: Sendable {
    static let scheme = "ssh-trust"

    static let supportedKeyTypes: Set<String> = [
        "ssh-ed25519",
        "ssh-rsa",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
    ]

    static func parse(_ uriString: String) throws -> ParsedFingerprint {
        guard let components = URLComponents(string: uriString) else {
            throw FingerprintURIParserError.invalidScheme
        }

        guard components.scheme == scheme else {
            throw FingerprintURIParserError.invalidScheme
        }

        guard let host = components.host, !host.isEmpty else {
            throw FingerprintURIParserError.missingHost
        }

        let port: UInt16
        if let p = components.port {
            guard p > 0, p <= UInt16.max else {
                throw FingerprintURIParserError.invalidPort
            }
            port = UInt16(p)
        } else {
            port = 22
        }

        let queryItems = components.queryItems ?? []

        guard let fpValue = queryItems.first(where: { $0.name == "fp" })?.value, !fpValue.isEmpty else {
            throw FingerprintURIParserError.missingFingerprint
        }

        guard fpValue.hasPrefix("SHA256:") else {
            throw FingerprintURIParserError.invalidFingerprintFormat
        }

        let base64Part = String(fpValue.dropFirst("SHA256:".count))
        guard !base64Part.isEmpty, base64Part.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }) else {
            throw FingerprintURIParserError.invalidFingerprintFormat
        }

        guard let keyType = queryItems.first(where: { $0.name == "type" })?.value, !keyType.isEmpty else {
            throw FingerprintURIParserError.missingKeyType
        }

        guard supportedKeyTypes.contains(keyType) else {
            throw FingerprintURIParserError.unsupportedKeyType(keyType)
        }

        return ParsedFingerprint(
            hostname: host,
            port: port,
            fingerprint: fpValue,
            keyType: keyType
        )
    }

    static func buildURI(hostname: String, port: UInt16, fingerprint: String, keyType: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = hostname
        if port != 22 {
            components.port = Int(port)
        }
        components.queryItems = [
            URLQueryItem(name: "fp", value: fingerprint),
            URLQueryItem(name: "type", value: keyType),
        ]
        return components.string ?? ""
    }
}
