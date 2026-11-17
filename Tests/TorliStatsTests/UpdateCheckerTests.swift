import Foundation
import XCTest
@testable import TorliStats

final class UpdateCheckerTests: XCTestCase {
    @MainActor
    func testCancelledCheckDoesNotAnnounceOrRecordSuccess() async {
        let domain = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = ControlledUpdateSession()
        let checker = AppUpdateChecker(defaults: defaults, session: session)
        var announcements = 0
        checker.check { _ in announcements += 1 }
        checker.check { _ in announcements += 1 }
        checker.cancelCheck()
        session.finishRequest(0, version: "99.0.0")
        await drainMainQueue()
        XCTAssertEqual(checker.status, .idle)
        XCTAssertEqual(announcements, 0)
        XCTAssertNil(defaults.object(forKey: "appUpdateLastCheckDate"))
    }

    @MainActor
    func testLateCancelledResponseCannotReplaceNewCheckResult() async {
        let domain = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = ControlledUpdateSession()
        let checker = AppUpdateChecker(defaults: defaults, session: session)
        var versions: [String?] = []
        checker.check { versions.append($0?.version) }
        checker.cancelCheck()
        checker.check { versions.append($0?.version) }
        session.finishRequest(0, version: "98.0.0")
        await drainMainQueue()
        XCTAssertEqual(checker.status, .checking)
        XCTAssertTrue(versions.isEmpty)
        checker.check { versions.append($0?.version) }
        session.finishRequest(1, version: "99.0.0")
        await drainMainQueue()
        XCTAssertEqual(versions, ["99.0.0", "99.0.0"])
        guard case let .available(release) = checker.status else {
            return XCTFail("The restarted check must retain its own result")
        }
        XCTAssertEqual(release.version, "99.0.0")
        XCTAssertNotNil(defaults.object(forKey: "appUpdateLastCheckDate"))
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

// Deliberately delivers completions even after cancel, to exercise the race
// where URLSession has already queued a response before the user closes the UI.
private final class ControlledUpdateSession: URLSession, @unchecked Sendable {
    private var callbacks: [@Sendable (Data?, URLResponse?, Error?) -> Void] = []

    override func dataTask(with request: URLRequest,
                           completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        callbacks.append(completionHandler)
        return ControlledUpdateTask()
    }

    func finishRequest(_ index: Int, version: String) {
        let url = URL(string: "https://github.com/JamesLi-dev/torli-stats/releases/tag/v\(version)")!
        callbacks[index](nil, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
    }
}

private final class ControlledUpdateTask: URLSessionDataTask, @unchecked Sendable {
    override func resume() {}
    override func cancel() {}
}
