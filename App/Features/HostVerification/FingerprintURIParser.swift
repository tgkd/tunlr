import Foundation
import CryptoKit

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
        guard let digest = decodeBase64(base64Part), digest.count == SHA256.byteCount else {
            throw FingerprintURIParserError.invalidFingerprintFormat
        }
        let canonicalFingerprint = "SHA256:" + digest.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        guard let keyType = queryItems.first(where: { $0.name == "type" })?.value, !keyType.isEmpty else {
            throw FingerprintURIParserError.missingKeyType
        }

        guard supportedKeyTypes.contains(keyType) else {
            throw FingerprintURIParserError.unsupportedKeyType(keyType)
        }

        return ParsedFingerprint(
            hostname: host,
            port: port,
            fingerprint: canonicalFingerprint,
            keyType: keyType
        )
    }

    static func decodeBase64(_ value: String) -> Data? {
        let unpadded = String(value.reversed().drop(while: { $0 == "=" }).reversed())
        guard !unpadded.isEmpty, !unpadded.contains("=") else { return nil }
        let padding = (4 - unpadded.count % 4) % 4
        guard value.count == unpadded.count + padding || value.count == unpadded.count else {
            return nil
        }
        return Data(base64Encoded: unpadded + String(repeating: "=", count: padding))
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
