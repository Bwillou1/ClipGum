import CryptoKit
import Foundation
import XCTest
@testable import ClipGum

actor MockModelDownloader: ModelFileDownloading {
    private(set) var calls: [URL] = []
    private let fixture: URL
    private let corrupt: Bool

    init(fixture: URL, corrupt: Bool = false) {
        self.fixture = fixture
        self.corrupt = corrupt
    }

    func download(_ url: URL, to destination: URL, expectedBytes: Int64) async throws {
        calls.append(url)
        var data = try Data(contentsOf: fixture)
        if corrupt, !data.isEmpty {
            data[0] ^= 0xFF
        }
        try data.write(to: destination)
    }
}

final class ModelDownloadTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipGumModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    private func fixture(named name: String = "model.gguf", bytes: Int = 32_768) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        var data = Data((0..<bytes).map { UInt8($0 % 251) })
        // Avoid a zero-length fixture and ensure corruption changes a real byte.
        if data.isEmpty { data = Data([1]) }
        try data.write(to: url)
        return url
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func manifest(
        file: String = "model.gguf",
        url: String = "https://models.example.com/model.gguf",
        expectedBytes: Int64,
        digest: String,
        identifier: String = "verified-test-model"
    ) -> ModelDownloadManifest {
        ModelDownloadManifest(
            formatVersion: 1,
            identifier: identifier,
            displayName: "Verified Test Model",
            backend: .gguf,
            minimumUnifiedRAMBytes: 4 * ModelReadiness.gibibyte,
            files: [ModelDownloadFile(name: file, url: URL(string: url)!, expectedBytes: expectedBytes, sha256: digest)]
        )
    }

    private var ready: ModelReadiness {
        ModelReadiness(
            isAppleSilicon: true,
            unifiedRAMBytes: 16 * ModelReadiness.gibibyte,
            requiredRAMBytes: 0
        )
    }

    func testVerifiedDownloadInstallsAtomically() async throws {
        let source = try fixture()
        let mock = MockModelDownloader(fixture: source)
        let service = ModelDownloadService(
            downloader: mock,
            baseDirectory: temporaryDirectory.appendingPathComponent("Models")
        )
        let model = try await service.install(
            manifest: manifest(
                expectedBytes: Int64((try Data(contentsOf: source)).count),
                digest: try sha256(source)
            ),
            readiness: ready
        )
        XCTAssertEqual(try Data(contentsOf: model.modelURL), try Data(contentsOf: source))
        let entries = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory.appendingPathComponent("Models"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(entries.map(\.lastPathComponent), ["verified-test-model"])
        let calls = await mock.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testTamperedDownloadIsDeletedAndNeverInstalled() async throws {
        let source = try fixture()
        let mock = MockModelDownloader(fixture: source, corrupt: true)
        let base = temporaryDirectory.appendingPathComponent("Models")
        let service = ModelDownloadService(downloader: mock, baseDirectory: base)
        do {
            _ = try await service.install(
                manifest: manifest(
                    expectedBytes: Int64((try Data(contentsOf: source)).count),
                    digest: try sha256(source)
                ),
                readiness: ready
            )
            XCTFail("Tampered model must be rejected")
        } catch {
            guard let modelError = error as? ModelDownloadError, case .digestMismatch = modelError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: base.appendingPathComponent("verified-test-model").path
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    func testByteCountMismatchIsRejectedBeforeHashAcceptance() throws {
        let source = try fixture()
        let file = ModelDownloadFile(
            name: "model.gguf",
            url: URL(string: "https://models.example.com/model.gguf")!,
            expectedBytes: Int64((try Data(contentsOf: source)).count + 1),
            sha256: try sha256(source)
        )
        XCTAssertThrowsError(try ModelIntegrityVerifier.verify(fileAt: source, expected: file)) {
            guard let modelError = $0 as? ModelDownloadError, case .byteCountMismatch = modelError else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    func testUnsafeManifestsFailBeforeTransport() async throws {
        let source = try fixture()
        let data = try Data(contentsOf: source)
        let digest = try sha256(source)
        let invalid = [
            manifest(file: "../escape.gguf", expectedBytes: Int64(data.count), digest: digest),
            manifest(url: "http://models.example.com/model.gguf", expectedBytes: Int64(data.count), digest: digest),
            manifest(expectedBytes: Int64(data.count), digest: "not-a-sha256"),
            manifest(expectedBytes: Int64.max, digest: digest)
        ]
        for invalidManifest in invalid {
            let mock = MockModelDownloader(fixture: source)
            let service = ModelDownloadService(
                downloader: mock,
                baseDirectory: temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
            do {
                _ = try await service.install(manifest: invalidManifest, readiness: ready)
                XCTFail("Invalid manifest must not install")
            } catch {
                XCTAssertTrue(error is ModelDownloadError)
            }
            let calls = await mock.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testInsufficientRAMSkipsNetwork() async throws {
        let source = try fixture()
        let mock = MockModelDownloader(fixture: source)
        let service = ModelDownloadService(
            downloader: mock,
            baseDirectory: temporaryDirectory.appendingPathComponent("Models")
        )
        let limited = ModelReadiness(
            isAppleSilicon: true,
            unifiedRAMBytes: 2 * ModelReadiness.gibibyte,
            requiredRAMBytes: 4 * ModelReadiness.gibibyte
        )
        do {
            _ = try await service.install(
                manifest: manifest(
                    expectedBytes: Int64((try Data(contentsOf: source)).count),
                    digest: try sha256(source)
                ),
                readiness: limited
            )
            XCTFail("Insufficient RAM must fail")
        } catch {
            guard let modelError = error as? ModelDownloadError, case .insufficientMemory = modelError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let calls = await mock.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testExistingDestinationIsNotOverwritten() async throws {
        let source = try fixture()
        let base = temporaryDirectory.appendingPathComponent("Models")
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("verified-test-model"),
            withIntermediateDirectories: true
        )
        let mock = MockModelDownloader(fixture: source)
        let service = ModelDownloadService(downloader: mock, baseDirectory: base)
        do {
            _ = try await service.install(
                manifest: manifest(
                    expectedBytes: Int64((try Data(contentsOf: source)).count),
                    digest: try sha256(source)
                ),
                readiness: ready
            )
            XCTFail("Existing model must not be replaced")
        } catch {
            guard let modelError = error as? ModelDownloadError, case .destinationExists = modelError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let calls = await mock.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testMLXManifestRequiresConfigAndWeights() throws {
        let config = ModelDownloadFile(
            name: "config.json",
            url: URL(string: "https://models.example.com/config.json")!,
            expectedBytes: 2,
            sha256: String(repeating: "a", count: 64)
        )
        let weights = ModelDownloadFile(
            name: "model.safetensors",
            url: URL(string: "https://models.example.com/model.safetensors")!,
            expectedBytes: 2,
            sha256: String(repeating: "b", count: 64)
        )
        let valid = ModelDownloadManifest(
            formatVersion: 1,
            identifier: "mlx-model",
            displayName: "MLX Model",
            backend: .mlx,
            minimumUnifiedRAMBytes: 0,
            files: [config, weights]
        )
        XCTAssertNoThrow(try valid.validated())
        let missingWeights = ModelDownloadManifest(
            formatVersion: 1,
            identifier: "mlx-model",
            displayName: "MLX Model",
            backend: .mlx,
            minimumUnifiedRAMBytes: 0,
            files: [config]
        )
        XCTAssertThrowsError(try missingWeights.validated())
    }

    func testReadinessUsesArchitectureAndDeclaredUnifiedRAM() {
        XCTAssertTrue(ready.canLoadModel)
        XCTAssertFalse(ModelReadiness(
            isAppleSilicon: false,
            unifiedRAMBytes: 64 * ModelReadiness.gibibyte,
            requiredRAMBytes: 0
        ).canLoadModel)
        XCTAssertFalse(ModelReadiness(
            isAppleSilicon: true,
            unifiedRAMBytes: 4 * ModelReadiness.gibibyte,
            requiredRAMBytes: 8 * ModelReadiness.gibibyte
        ).canLoadModel)
    }
}
