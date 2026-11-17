import Foundation
import XCTest
@testable import TorliStats

final class UpdateDownloadTests: XCTestCase {
    func testArchiveProgressUsesReceivedBytesAndThrottlesChunks() {
        let finished = expectation(description: "download finished")
        var samples: [(received: Int64, total: Int64?)] = []
        download("known", progress: { value in
            XCTAssertTrue(Thread.isMainThread)
            guard case let .downloading(received, total) = value else {
                return XCTFail("Unexpected archive progress phase")
            }
            samples.append((received, total))
        }) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(try? result.get().count, ControlledUpdateProtocol.byteCount)
            XCTAssertEqual(samples.first?.received, 0)
            XCTAssertEqual(samples.last?.received, Int64(ControlledUpdateProtocol.byteCount))
            XCTAssertTrue(samples.allSatisfy { $0.total == Int64(ControlledUpdateProtocol.byteCount) })
            XCTAssertEqual(samples.map(\.received), samples.map(\.received).sorted())
            XCTAssertLessThan(samples.count, ControlledUpdateProtocol.chunkCount / 2)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }

    func testUnknownLengthStaysIndeterminateThroughCompletion() {
        let finished = expectation(description: "unknown-length download finished")
        var samples: [(received: Int64, total: Int64?)] = []
        download("unknown", progress: { value in
            guard case let .downloading(received, total) = value else {
                return XCTFail("Unexpected archive progress phase")
            }
            samples.append((received, total))
        }) { result in
            XCTAssertEqual(try? result.get().count, ControlledUpdateProtocol.byteCount)
            XCTAssertFalse(samples.isEmpty)
            XCTAssertTrue(samples.allSatisfy { $0.total == nil })
            XCTAssertEqual(samples.last?.received, Int64(ControlledUpdateProtocol.byteCount))
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }

    func testEmptyResponseDoesNotInventAnExpectedTotal() {
        let finished = expectation(description: "empty download finished")
        var received: [Int64] = []
        download("empty", progress: { value in
            guard case let .downloading(bytes, total) = value else {
                return XCTFail("Unexpected archive progress phase")
            }
            received.append(bytes)
            XCTAssertNil(total)
        }) { result in
            XCTAssertEqual(try? result.get(), Data())
            XCTAssertEqual(received, [0])
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }

    func testChecksumDownloadDoesNotEmitArchiveProgress() {
        let finished = expectation(description: "checksum download finished")
        download("known", reportProgress: false, progress: { _ in
            XCTFail("Checksum downloads must not report archive progress")
        }) { result in
            XCTAssertEqual(try? result.get().count, ControlledUpdateProtocol.byteCount)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }

    func testCancellationBeforeRegistrationNeverResumesRequest() {
        let task = UpdatePreparationTask()
        task.cancel()
        let session = URLSession(configuration: configuration())
        defer { session.invalidateAndCancel() }
        let request = session.dataTask(with: url("must-not-start"))
        XCTAssertThrowsError(try task.start(request)) { assertCancelled($0) }
        XCTAssertEqual(request.state, .suspended)
    }

    func testPrecancelledDownloadDoesNotStartOrWaitForRequest() {
        let finished = expectation(description: "pre-cancelled download finished")
        let task = UpdatePreparationTask(progress: { _ in XCTFail("Cancelled progress was delivered") })
        task.cancel()
        let config = configuration()
        let destination = url("must-not-start")
        DispatchQueue.global().async {
            let result = Result { try UpdateDownload.get(destination, limit: 1024, task: task, reportProgress: true, configuration: config) }
            task.complete(result) { result in
                XCTAssertTrue(Thread.isMainThread)
                switch result {
                case .success: XCTFail("Cancelled download succeeded")
                case let .failure(error): assertCancelled(error)
                }
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 5)
    }

    func testCancellationFromProgressStopsAnActiveRequestWithoutDeadlock() {
        let finished = expectation(description: "active download cancelled")
        var task: UpdatePreparationTask?
        var progressCount = 0
        DispatchQueue.main.async {
            task = self.download("stalled", progress: { value in
                XCTAssertTrue(Thread.isMainThread)
                guard case let .downloading(received, total) = value else {
                    return XCTFail("Unexpected archive progress phase")
                }
                XCTAssertEqual(received, 0)
                XCTAssertEqual(total, Int64(ControlledUpdateProtocol.byteCount))
                progressCount += 1
                task?.cancel()
            }) { result in
                switch result {
                case .success: XCTFail("Cancelled download succeeded")
                case let .failure(error): assertCancelled(error)
                }
                XCTAssertEqual(progressCount, 1)
                task = nil
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 5)
    }

    func testCancellationSuppressesQueuedProgressAndSuccess() {
        let finished = expectation(description: "cancelled completion delivered")
        let released = expectation(description: "cancelled prepared value released")
        let task = UpdatePreparationTask(progress: { _ in XCTFail("Queued progress survived cancellation") })
        DispatchQueue.main.async {
            task.report(.preparing)
            task.report(.verifying)
            task.complete(.success(ReleaseProbe { released.fulfill() })) { result in
                XCTAssertTrue(Thread.isMainThread)
                switch result {
                case .success: XCTFail("Queued success survived cancellation")
                case let .failure(error): assertCancelled(error)
                }
                finished.fulfill()
            }
            task.cancel()
        }
        wait(for: [finished, released], timeout: 5)
    }

    func testPrepareImmediateCancellationIsDeliveredOnMainQueue() {
        let finished = expectation(description: "preparation cancelled")
        let release = AppUpdateRelease(version: "1.2.3", downloadURL: URL(string: "https://github.com/JamesLi-dev/torli-stats/releases/tag/v1.2.3")!, publishedAt: nil)
        DispatchQueue.main.async {
            let task = AppUpdateInstaller().prepare(release: release, progress: { _ in
                XCTFail("Queued preparation progress survived cancellation")
            }) { result in
                XCTAssertTrue(Thread.isMainThread)
                switch result {
                case .success: XCTFail("Cancelled preparation succeeded")
                case let .failure(error): assertCancelled(error)
                }
                finished.fulfill()
            }
            task.cancel()
        }
        wait(for: [finished], timeout: 5)
    }

    func testOversizedResponseIsRejectedBeforeProgress() {
        let finished = expectation(description: "oversized response rejected")
        download("oversized", progress: { _ in XCTFail("Rejected response reported progress") }) { result in
            if case .success = result { XCTFail("Oversized download succeeded") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }

    @discardableResult
    private func download(_ scenario: String, reportProgress: Bool = true, progress: @escaping (UpdatePreparationProgress) -> Void, completion: @escaping (Result<Data, Error>) -> Void) -> UpdatePreparationTask {
        let task = UpdatePreparationTask(progress: progress)
        let config = configuration()
        let destination = url(scenario)
        DispatchQueue.global().async {
            let result = Result { try UpdateDownload.get(destination, limit: ControlledUpdateProtocol.byteCount, task: task, reportProgress: reportProgress, configuration: config) }
            task.complete(result, completion: completion)
        }
        return task
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledUpdateProtocol.self]
        return configuration
    }

    private func url(_ scenario: String) -> URL {
        URL(string: "https://github.com/JamesLi-dev/torli-stats/releases/download/v1.2.3/\(scenario)")!
    }
}

private func assertCancelled(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    let error = error as NSError
    XCTAssertEqual(error.domain, NSURLErrorDomain, file: file, line: line)
    XCTAssertEqual(error.code, URLError.cancelled.rawValue, file: file, line: line)
}

private final class ReleaseProbe {
    private let released: () -> Void
    init(released: @escaping () -> Void) { self.released = released }
    deinit { released() }
}

private final class ControlledUpdateProtocol: URLProtocol {
    static let chunkCount = 128
    static let chunkSize = 16 * 1024
    static let byteCount = chunkCount * chunkSize

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return XCTFail("Missing test URL") }
        let scenario = url.lastPathComponent
        guard scenario != "must-not-start" else {
            XCTFail("A cancelled request was started")
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        // Avoid MIME sniffing buffering the header-only stalled response.
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        if scenario != "unknown" {
            let length = scenario == "empty" ? 0 : Self.byteCount + (scenario == "oversized" ? 1 : 0)
            headers["Content-Length"] = String(length)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if scenario == "stalled" || scenario == "oversized" { return }
        if scenario != "empty" {
            let chunk = Data(repeating: 0x61, count: Self.chunkSize)
            for _ in 0..<Self.chunkCount { client?.urlProtocol(self, didLoad: chunk) }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
