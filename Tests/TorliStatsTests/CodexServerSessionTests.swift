import XCTest
@testable import TorliStats

final class CodexServerSessionTests: XCTestCase {
    func testUnauthorizedAccountReadIsNotIgnored() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try script(at: root, content: """
            #!/bin/sh
            while IFS= read -r line; do
                case "$line" in
                    *'"method":"initialize"'*) echo '{"id":1,"result":{}}' ;;
                    *'account'*'read'*) echo '{"id":2,"error":{"code":-32000,"data":{"status":401},"message":"expired"}}' ;;
                esac
            done
            """)
        let done = expectation(description: "unauthorized")
        let session = CodexServerSession(executable: executable, home: root) { result in
            guard case .failure(.unauthorized) = result else { XCTFail("Expected unauthorized"); done.fulfill(); return }
            done.fulfill()
        }
        session.start()
        await fulfillment(of: [done], timeout: 5)
        session.cancel()
        session.waitForExit()
    }

    func testAccountsSerializeServersAndCancelledQueueEntryNeverLaunches() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try script(at: root, content: """
            #!/bin/sh
            if ! mkdir "$CODEX_HOME/running" 2>/dev/null; then echo overlap >> "$CODEX_HOME/overlap"; fi
            trap 'rmdir "$CODEX_HOME/running"; exit 0' TERM EXIT
            echo started >> "$CODEX_HOME/starts"
            while IFS= read -r line; do
                case "$line" in
                    *'"method":"initialize"'*) sleep 0.15; echo '{"id":1,"result":{}}' ;;
                    *'rateLimits'*) echo '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":25}}}}' ;;
                    *'account'*'read'*) echo '{"id":2,"result":{"account":{"email":"test@example.test"}}}' ;;
                esac
            done
            """)
        let done = expectation(description: "both accounts")
        done.expectedFulfillmentCount = 2
        let clientA = CodexUsageClient(homePathProvider: { root.path }, executableProvider: { executable })
        let clientB = CodexUsageClient(homePathProvider: { root.path }, executableProvider: { executable })
        let first = clientA.fetch(preferLocal: false) { result in
            if case .failure = result { XCTFail("First account failed") }
            done.fulfill()
        }
        let cancelled = clientB.fetch(preferLocal: false) { _ in XCTFail("Cancelled request completed") }
        cancelled.cancel()
        let second = clientB.fetch(preferLocal: false) { result in
            if case .failure = result { XCTFail("Second account failed") }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 8)
        first.cancel(); second.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("overlap").path))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("starts"), encoding: .utf8).split(separator: "\n").count, 2)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("auth.json"))
        return root
    }

    private func script(at root: URL, content: String) throws -> URL {
        let url = root.appendingPathComponent("fake-codex")
        try Data((content + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
