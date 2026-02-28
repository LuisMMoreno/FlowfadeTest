import Foundation
import CommonCrypto

struct FileHasher {
    /// Generate a SHA256 hash of the first N bytes of a file for identification.
    /// Uses partial hashing for performance — we don't need to read the entire file.
    static func hash(fileAt url: URL, byteCount: Int = Constants.hashByteCount) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { fileHandle.closeFile() }

        let data = fileHandle.readData(ofLength: byteCount)
        guard !data.isEmpty else { return nil }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
