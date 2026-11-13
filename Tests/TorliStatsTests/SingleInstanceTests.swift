import Darwin
import XCTest
@testable import TorliStats

final class SingleInstanceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSecondLaunchIsRejectedAndNormalExitReleasesLock() throws {
        let url = directory.appendingPathComponent("instance.lock")
        var first: ApplicationInstanceLock? = ApplicationInstanceLock()
        XCTAssertTrue(try first!.acquire(at: url))
        let second = ApplicationInstanceLock()
        XCTAssertFalse(try second.acquire(at: url))
        first = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try second.acquire(at: url), "The persistent file must not block a relaunch")
        withExtendedLifetime(second) {}
    }

    func testOldLockFileDoesNotBlockStartup() throws {
        let url = directory.appendingPathComponent("instance.lock")
        try Data("old PID".utf8).write(to: url)
        let instanceLock = ApplicationInstanceLock()
        XCTAssertTrue(try instanceLock.acquire(at: url))
        withExtendedLifetime(instanceLock) {}
    }

    func testSimultaneousLaunchesHaveExactlyOneOwner() {
        let url = directory.appendingPathComponent("instance.lock")
        let contenders = (0..<12).map { _ in ApplicationInstanceLock() }
        let resultsLock = NSLock()
        var results: [Result<Bool, Error>] = []
        DispatchQueue.concurrentPerform(iterations: contenders.count) { index in
            let result = Result { try contenders[index].acquire(at: url) }
            resultsLock.lock()
            results.append(result)
            resultsLock.unlock()
        }
        XCTAssertEqual(results.compactMap { try? $0.get() }.count, 12)
        XCTAssertEqual(results.compactMap { try? $0.get() }.filter { $0 }.count, 1)
        withExtendedLifetime(contenders) {}
    }

    func testDifferentApplicationLocksCanRunIndependently() throws {
        let first = ApplicationInstanceLock(), second = ApplicationInstanceLock()
        XCTAssertTrue(try first.acquire(at: directory.appendingPathComponent("first.lock")))
        XCTAssertTrue(try second.acquire(at: directory.appendingPathComponent("second.lock")))
        withExtendedLifetime((first, second)) {}
    }

    func testLockAccessFailureIsNotMistakenForAnotherInstance() {
        let instanceLock = ApplicationInstanceLock()
        XCTAssertThrowsError(try instanceLock.acquire(at: directory.appendingPathComponent("missing/instance.lock")))
    }

    func testLockDoesNotFollowSymbolicLinks() throws {
        let target = directory.appendingPathComponent("target")
        try Data().write(to: target)
        let link = directory.appendingPathComponent("instance.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ApplicationInstanceLock().acquire(at: link))
    }

    func testOtherProcessIsExcludedAndCrashReleasesLock() throws {
        let url = directory.appendingPathComponent("instance.lock")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-MFcntl=:flock", "-e", """
        open(my $file, '>>', $ARGV[0]) or die $!;
        flock($file, LOCK_EX | LOCK_NB) or die $!;
        $| = 1; print 'R'; sleep 30;
        """, url.path]
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        XCTAssertEqual(try output.fileHandleForReading.read(upToCount: 1), Data("R".utf8))
        let contender = ApplicationInstanceLock()
        XCTAssertFalse(try contender.acquire(at: url))
        kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()
        XCTAssertTrue(try contender.acquire(at: url), "A crash must not leave the app locked out")
        withExtendedLifetime(contender) {}
    }

    func testReopenDuringStartupIsDeliveredOnceWhenReady() {
        let controller = SingleInstanceController(identifier: "test." + UUID().uuidString)
        var presentations = 0
        controller.requestActivation()
        controller.requestActivation()
        XCTAssertEqual(presentations, 0)
        controller.whenReady { presentations += 1 }
        XCTAssertEqual(presentations, 1)
        controller.requestActivation()
        XCTAssertEqual(presentations, 2)
    }

    func testNormalStartupDoesNotOpenDashboard() {
        let controller = SingleInstanceController(identifier: "test." + UUID().uuidString)
        var presentations = 0
        controller.whenReady { presentations += 1 }
        XCTAssertEqual(presentations, 0)
    }
}
