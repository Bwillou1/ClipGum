import Foundation

actor BoundedModelFileDownloader: ModelFileDownloading {
    func download(_ url: URL, to destination: URL, expectedBytes: Int64) async throws {
        guard HTTPSURLPolicy.isValid(url) else {
            throw ModelDownloadError.downloadRejected
        }
        _ = try await BoundedDownloadTask.download(
            url: url,
            destination: destination,
            expectedBytes: expectedBytes
        )
    }
}

/// One ephemeral, cookieless, credentialless session per explicit file. The
/// delegate cancels oversized responses and refuses HTTPS-to-other redirects.
private final class BoundedDownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedBytes: Int64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadResult: Result<URL, Error>?
    private var session: URLSession?
    private var rejected = false

    private init(destination: URL, expectedBytes: Int64) {
        self.destination = destination
        self.expectedBytes = expectedBytes
    }

    static func download(url: URL, destination: URL, expectedBytes: Int64) async throws -> URL {
        let task = BoundedDownloadTask(destination: destination, expectedBytes: expectedBytes)
        return try await task.start(url: url)
    }

    private func start(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 3_600
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let downloadTask = session.downloadTask(with: request)
            lock.unlock()
            downloadTask.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let exceedsDeclaredSize = totalBytesWritten > expectedBytes
            || (totalBytesExpectedToWrite >= 0 && totalBytesExpectedToWrite > expectedBytes)
        if exceedsDeclaredSize {
            lock.lock()
            rejected = true
            lock.unlock()
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard HTTPSURLPolicy.isValid(request.url) else {
            lock.lock()
            rejected = true
            lock.unlock()
            task.cancel()
            completionHandler(nil)
            return
        }
        var safeRequest = request
        safeRequest.httpShouldHandleCookies = false
        safeRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        safeRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(safeRequest)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let result: Result<URL, Error>
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            result = .success(destination)
        } catch {
            result = .failure(error)
        }
        lock.lock()
        downloadResult = result
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let storedResult = downloadResult
        let wasRejected = rejected
        lock.unlock()
        if let storedResult {
            finish(storedResult)
        } else if wasRejected {
            finish(.failure(ModelDownloadError.downloadRejected))
        } else if let error {
            finish(.failure(error))
        } else {
            finish(.failure(ModelDownloadError.downloadRejected))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
