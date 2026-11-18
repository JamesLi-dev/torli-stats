import Foundation
import XCTest
@testable import TorliStats

final class CompressedTokenActivityTests: XCTestCase {
    // Fixed frames created with upstream zstd 1.5.7. No external decoder is needed by the tests.
    private let first = Data(base64Encoded: "KLUv/QRYRQMAggYWGoC5OdiLmkwSWtRrL4i8OUzcVAFtUlFHJfoJgNZa+8+ZJYJsQQqu6kElNl61aAGpROieDaiKApeNCf/9dz74MQQ3AscPn1fCZZmStTHCElqVifQ5l2K9CAQAOLv+ORrQGwKiCFGf3OcP")!
    private let second = Data(base64Encoded: "KLUv/QRYPQMAcsYVGoC5OdiLmkwSWtRrL4i8OUzcFA52UlFHUR8BrbX245xZIsgWpOCqFlRi41WLDpBKg+6ZgKogcNlY8N9/54GfAvDiMG74vBIuy5SsjRGW0Ko8pM+5EOtEBAA4u/45GtAbAqIIUWnN1Eo=")!
    private let large = Data(base64Encoded: "KLUv/QRYVAAAEHh4AQD7/znAAgIAEHgCABB4AgAQeAIAEHgCABB4AgAQeAIAEHgJAAB4DrFrzw==")!
    private let replacement = Data(base64Encoded: "KLUv/QRYRQMAggYWGoC5OdiOTDkttKjXXhB5c5i4KRzspKKOSvQTgNZa+4HOLBFkTFJwVQ0r8fEuRglp5UH3XEBVGlx8PPjvP3TBURF4cRg3fF4ULkuVrI8RptKuRKTPuTTrRAQAOLv+ORrQGwKiCFEoIuA+")!

    func testFramesPartialLinesAndCorruptInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.jsonl.zst")
        try (first + second).write(to: file)
        XCTAssertEqual(try CodexTokenActivityService.read(file).map(\.tokens), [100, 60])
        try Data(first.dropLast()).write(to: file)
        XCTAssertThrowsError(try CodexTokenActivityService.read(file))
        try (first + Data("invalid".utf8)).write(to: file)
        XCTAssertThrowsError(try CodexTokenActivityService.read(file))
        try Data().write(to: file)
        XCTAssertThrowsError(try CodexTokenActivityService.read(file))
        try large.write(to: file)
        let reader = try ZstdFileReader(url: file)
        var count = 0
        while let chunk = try reader.read() { count += chunk.count }
        XCTAssertEqual(count, 1_048_577)
    }

    @MainActor
    func testExistingIndexFindsCompressedHistoryDeduplicatesAndRebuildsChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let archive = root.appendingPathComponent("archived_sessions")
        for url in [sessions, archive] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let log = sessions.appendingPathComponent("test.jsonl")
        let compressed = archive.appendingPathComponent("test.jsonl.zst")
        let plain = "{\"type\":\"event_msg\",\"timestamp\":\"2026-09-10T01:00:00Z\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":100}}}}\n"
        try Data(plain.utf8).write(to: log)
        let cache = root.appendingPathComponent("cache")
        let old = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        old.setEnabled(true)
        try await wait(old)
        old.setEnabled(false)
        XCTAssertEqual(old.records.map(\.value), [100])
        try first.write(to: compressed)
        let service = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        service.setEnabled(true)
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [100])
        try FileManager.default.removeItem(at: log)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [100])
        // Recompression or a newly appended frame replaces the compressed file's event set.
        try (replacement + replacement).write(to: compressed)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [160])
        try Data(second.dropLast()).write(to: compressed)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [160], "Damaged sources retain the last valid index")
        XCTAssertNotNil(service.status)
        try second.write(to: compressed)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [160])
        let databases = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        let database = try XCTUnwrap(databases.first { $0.pathExtension == "sqlite" })
        let before = try Data(contentsOf: database)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(try Data(contentsOf: database), before)
        service.setEnabled(false)
    }

    @MainActor private func wait(_ service: CodexTokenActivityService) async throws {
        for _ in 0..<500 where service.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(service.isLoading)
    }
}
