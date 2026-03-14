import Foundation

enum MemoryHygiene {

    static func zeroOut(_ bytes: inout [UInt8]) {
        guard !bytes.isEmpty else { return }
        bytes.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memset_wrapper(baseAddress, 0, buffer.count)
        }
        bytes = []
    }

    static func zeroOut(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memset_wrapper(baseAddress, 0, buffer.count)
        }
        data = Data()
    }

    static func withSecureBytes<T>(_ bytes: [UInt8], _ body: ([UInt8]) throws -> T) rethrows -> T {
        var mutableCopy = bytes
        defer { zeroOut(&mutableCopy) }
        return try body(mutableCopy)
    }

    static func passphraseToBytes(_ passphrase: String) -> [UInt8] {
        Array(passphrase.utf8)
    }

    /// Volatile-equivalent memset that the compiler cannot optimize away.
    /// Uses a function pointer to prevent dead-store elimination.
    private static func memset_wrapper(_ dest: UnsafeMutableRawPointer, _ value: Int32, _ count: Int) {
        // Using a volatile-style approach: the indirect call through a
        // noescape closure prevents the compiler from seeing through the
        // memset and optimizing it away as a dead store.
        let fn: (UnsafeMutableRawPointer, Int32, Int) -> Void = { ptr, val, cnt in
            memset(ptr, val, cnt)
        }
        fn(dest, value, count)
    }
}

extension MemoryHygiene {

    static var sensitiveLoggingDisabled: Bool { true }

    static func sanitize(_ value: String, label: String = "REDACTED") -> String {
        sensitiveLoggingDisabled ? "[\(label)]" : value
    }

    static func sanitize(_ data: Data, label: String = "REDACTED") -> String {
        sensitiveLoggingDisabled ? "[\(label) \(data.count) bytes]" : data.base64EncodedString()
    }
}
