import AppKit
import Foundation
import XCTest
@testable import ClipGum

private final class RequestRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var recordedCount = 0

    static func reset() {
        lock.lock()
        recordedCount = 0
        lock.unlock()
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedCount += 1
        Self.lock.unlock()
        client?.urlProtocol(
            self,
            didFailWithError: NSError(domain: "ClipGumNetworkIsolationTest", code: 1)
        )
    }

    override func stopLoading() {}
}

@MainActor
final class NetworkIsolationTests: XCTestCase {
    func testCopyTransformPasteCycleMakesZeroOutboundRequests() throws {
        RequestRecordingURLProtocol.reset()
        XCTAssertTrue(URLProtocol.registerClass(RequestRecordingURLProtocol.self))
        defer { URLProtocol.unregisterClass(RequestRecordingURLProtocol.self) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipGumNetworkTest.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(
            "https://example.com/article?utm_source=private-token&id=42",
            forType: .string
        ))
        let systemPasteboard = SystemPasteboard(pasteboard: pasteboard)
        let captured = systemPasteboard.readDocumentForExplicitUserAction()
        let original: String
        switch captured {
        case .document(let document): original = try XCTUnwrap(document.plainText)
        case .text(let text): original = text
        default: return XCTFail("Expected explicit text capture")
        }

        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        let result = try XCTUnwrap(pipeline.mechanicalResult(
            action: .urlClean,
            input: original,
            document: nil
        ))
        let posted = expectation(description: "explicit test paste")
        let service = PasteService(
            pasteboard: systemPasteboard,
            accessibilityTrusted: { _ in true },
            applicationActivator: { _ in },
            keystrokePoster: { posted.fulfill() },
            focusSettleDelay: 0
        )
        try service.copyResult(result.cleaned)
        try service.paste(result.cleaned, to: nil)
        wait(for: [posted], timeout: 1)
        XCTAssertFalse(result.cleaned.contains("utm_source"))
        XCTAssertEqual(RequestRecordingURLProtocol.count, 0)
    }

    func testClipboardInferenceTransformationAndPastePathsHaveNoNetworkCallSites() throws {
        let roots = [
            "Core/Clipboard", "Core/Paste", "Core/Inference", "Services/Pipeline",
            "Services/Dev", "Services/Office", "Services/Diagnostics", "UI/Palette"
        ]
        let forbidden = ["URLSession", "NSURLConnection", "NWConnection", "URLProtocol", "WKWebView"]
        for file in productionFiles(relativeRoots: roots) {
            if file.lastPathComponent == "APIInferenceEngine.swift" {
                continue
            }
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }

    func testProductionRegistersNoContentLoggerOrCrashReporter() throws {
        let forbidden = [
            "os_log", "OSLog", "NSLog(", "Logger(", "print(", "debugPrint(",
            "NSSetUncaughtExceptionHandler", "Crashlytics", "Sentry", "MetricKit"
        ]
        for file in productionFiles(relativeRoots: [""]) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }

    func testEntitlementsAndUpdateMetadataRemainMinimal() throws {
        let root = repositoryRoot()
        let entitlementData = try Data(contentsOf: root.appendingPathComponent("Resources/ClipGum.entitlements"))
        let entitlements = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: entitlementData,
            options: [],
            format: nil
        ) as? [String: Any])
        XCTAssertEqual(Set(entitlements.keys), [
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.network.client",
            "com.apple.security.network.server",
            "com.apple.security.temporary-exception.mach-lookup.global-name"
        ])
        for key in entitlements.keys {
            XCTAssertFalse(key.contains("camera"))
            XCTAssertFalse(key.contains("microphone"))
            XCTAssertFalse(key.contains("location"))
            XCTAssertFalse(key.contains("allow-jit"))
            XCTAssertFalse(key.contains("unsigned-executable"))
            XCTAssertFalse(key.contains("disable-library-validation"))
        }

        let infoData = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: infoData,
            options: [],
            format: nil
        ) as? [String: Any])
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUEnableDownloaderService"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertNil(info["NSAppTransportSecurity"])
        XCTAssertNil(info["NSCameraUsageDescription"])
        XCTAssertNil(info["NSMicrophoneUsageDescription"])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func productionFiles(relativeRoots: [String]) -> [URL] {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources/ClipGum")
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let relative = url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            return relativeRoots.contains(where: { root in
                root.isEmpty || relative.hasPrefix(root + "/")
            }) ? url : nil
        }
    }
}
