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
