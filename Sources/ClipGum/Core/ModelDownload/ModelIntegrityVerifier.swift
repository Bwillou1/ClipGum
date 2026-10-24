import CryptoKit
import Foundation

enum ModelIntegrityVerifier {
    static func verify(fileAt url: URL, expected: ModelDownloadFile) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value == expected.expectedBytes else {
            throw ModelDownloadError.byteCountMismatch
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        var hasherError: Error?
        var total: Int64 = 0
        do {
            while true {
                let data = try autoreleasepool { try handle.read(upToCount: 1_048_576) }
                guard let data, !data.isEmpty else { break }
                total += Int64(data.count)
                guard total <= expected.expectedBytes else {
                    throw ModelDownloadError.byteCountMismatch
                }
                digest.update(data: data)
            }
        } catch {
            hasherError = error
        }
        if let hasherError {
            throw hasherError
        }
        guard total == expected.expectedBytes else {
            throw ModelDownloadError.byteCountMismatch
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected.sha256.lowercased() else {
            throw ModelDownloadError.digestMismatch
        }
    }
}
