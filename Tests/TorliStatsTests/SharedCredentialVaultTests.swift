import XCTest
@testable import TorliStats

final class SharedCredentialVaultTests: XCTestCase {
    func testNamespacesSurviveConcurrentWrites() throws {
        let backend = MemoryCredentialBackend()
        let vault = SharedCredentialVault(backend: backend)
        let failures = NSLock(); var errors = 0
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            do { try vault.write(Data([UInt8(index)]), for: "feature-\(index)") }
            catch { failures.lock(); errors += 1; failures.unlock() }
        }
        XCTAssertEqual(errors, 0)
        for index in 0..<24 { XCTAssertEqual(try vault.read("feature-\(index)"), Data([UInt8(index)])) }
    }
    func testMigrationRunsOnceAndTombstonePreventsResurrection() throws {
        let backend = MemoryCredentialBackend(); let vault = SharedCredentialVault(backend: backend)
        var reads = 0
        let legacy = { reads += 1; return Data("synthetic".utf8) }
        XCTAssertEqual(try vault.read("oauth", migrating: legacy), Data("synthetic".utf8))
        try vault.write(Data(), for: "oauth")
        XCTAssertEqual(try vault.read("oauth", migrating: legacy), Data())
        XCTAssertEqual(reads, 1)
    }
    func testDeniedOrMalformedReadNeverMigratesOrOverwrites() {
        for denied in [false, true] {
            let backend = MemoryCredentialBackend(); backend.data = Data("bad".utf8); backend.deny = denied
            let vault = SharedCredentialVault(backend: backend)
            XCTAssertThrowsError(try vault.read("mail") { XCTFail("must not fall back"); return Data() })
            XCTAssertThrowsError(try vault.write(Data(), for: "totp"))
            XCTAssertEqual(backend.writes, 0)
        }
    }
    func testWriteVerificationFailureIsReported() {
        let backend = MemoryCredentialBackend(); backend.dropWrites = true
        XCTAssertThrowsError(try SharedCredentialVault(backend: backend).write(Data([1]), for: "mail"))
    }
}
private final class MemoryCredentialBackend: CredentialVaultBackend {
    var data: Data?; var deny = false; var dropWrites = false; var writes = 0
    func read() throws -> Data? { if deny { throw CredentialVaultError.malformed }; return data }
    func write(_ value: Data) throws { writes += 1; if !dropWrites { data = value } }
}
