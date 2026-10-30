import AppKit
import XCTest
@testable import TorliStats

final class NotesImageStorageTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ImageStore.directoryOverride = folder.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        ImageStore.directoryOverride = nil
        try FileManager.default.removeItem(at: folder)
    }
    private func png(width: Int = 80, height: Int = 60) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<height {
            for x in 0..<width { bitmap.setColor(y < height / 2 ? NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y) }
        }
        return bitmap.representation(using: .png, properties: [:])!
    }
    func testOriginalPixelsAndTopLeftCrop() throws {
        let bytes = png(width: 2400, height: 40)
        let id = try ImageStore.saveValidated(data: bytes)
        XCTAssertEqual(ImageStore.data(id: id), bytes)
        XCTAssertEqual(ImageStore.image(id: id)?.size.width, 2400)
        let cropped = try XCTUnwrap(ImageStore.crop(id: id, normalizedRect: NSRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        let output = try XCTUnwrap(ImageStore.data(id: cropped))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(bitmap.pixelsWide, 1200)
        XCTAssertEqual(bitmap.pixelsHigh, 20)
        let color = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
        XCTAssertEqual(ImageStore.data(id: id), bytes)
    }
    func testArchiveRoundTripUsesFreshAssetsAndPreservesMetadata() throws {
        let bytes = png()
        let id = try ImageStore.saveValidated(data: bytes)
        var note = Note(body: "Title\n" + ImageStore.token(id: id, width: 320))
        note.pinned = true; note.archived = true
        let archive = try NoteImageTransfer.encodeArchive([note])
        let restored = try XCTUnwrap(NoteImageTransfer.decodeArchive(archive).first)
        let token = try XCTUnwrap(ImageStore.tokens(in: restored.body).first)
        XCTAssertNotEqual(token.id, id)
        XCTAssertEqual(token.width, 320)
        XCTAssertEqual(ImageStore.data(id: token.id), bytes)
        XCTAssertTrue(restored.pinned); XCTAssertTrue(restored.archived)
        XCTAssertEqual(restored.id, note.id)
        let second = try XCTUnwrap(NoteImageTransfer.decodeArchive(archive).first)
        XCTAssertNotEqual(ImageStore.tokens(in: second.body).first?.id, token.id)
    }
    func testMissingArchiveAssetFailsWithoutWriting() throws {
        let id = try ImageStore.saveValidated(data: png())
        let note = Note(body: ImageStore.token(id: id, width: nil) + "\n" + ImageStore.token(id: "missing", width: nil))
        XCTAssertThrowsError(try NoteImageTransfer.encodeArchive([note]))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let archive = StickyArchive(notes: [StickyNote(note)], images: [id: png().base64EncodedString()])
        let before = Set(ImageStore.allIDs())
        XCTAssertThrowsError(try NoteImageTransfer.decodeArchive(encoder.encode(archive)))
        XCTAssertEqual(Set(ImageStore.allIDs()), before)
    }
    func testMarkdownRoundTripAndExternalPaths() throws {
        let bytes = png()
        let id = try ImageStore.saveValidated(data: bytes)
        let source = "Title\n" + ImageStore.token(id: id, width: 240)
        let exported = try NoteImageTransfer.exportMarkdown(source, directory: folder, assetFolder: "images")
        XCTAssertTrue(exported.contains("![image|240](images/"))
        XCTAssertFalse(exported.contains("torli-img"))
        let imported = try NoteImageTransfer.importMarkdown(exported, relativeTo: folder)
        let token = try XCTUnwrap(ImageStore.tokens(in: imported).first)
        XCTAssertEqual(token.width, 240)
        XCTAssertEqual(ImageStore.data(id: token.id), bytes)
        XCTAssertNotEqual(token.id, id)
        let before = Set(ImageStore.allIDs())
        XCTAssertThrowsError(try NoteImageTransfer.importMarkdown("![](../outside.png)", relativeTo: folder))
        XCTAssertThrowsError(try NoteImageTransfer.importMarkdown("![](/tmp/outside.png)", relativeTo: folder))
        let remote = "![](https://example.com/image.png)"
        XCTAssertEqual(try NoteImageTransfer.importMarkdown(remote, relativeTo: folder), remote)
        XCTAssertEqual(Set(ImageStore.allIDs()), before)
    }
    func testInvalidInputsAndOrphanCleanup() throws {
        XCTAssertThrowsError(try ImageStore.saveValidated(data: Data("bad image".utf8)))
        XCTAssertThrowsError(try ImageStore.validate(Data(repeating: 0, count: ImageStore.maximumBytes + 1)))
        XCTAssertNil(ImageStore.fileURL(id: "../outside"))
        let keep = try ImageStore.saveValidated(data: png())
        let orphan = try ImageStore.saveValidated(data: png())
        var archived = Note(body: ImageStore.token(id: keep, width: nil)); archived.archived = true
        ImageStore.removeOrphans(referencedBy: [archived])
        XCTAssertNotNil(ImageStore.data(id: keep))
        XCTAssertNil(ImageStore.data(id: orphan))
        XCTAssertEqual(ImageStore.tokens(in: "![image](noty-img://OLD-ID)").first?.id, "OLD-ID")
    }

    func testInsertionResizeAndCropUndoRetainOriginalAsset() throws {
        let id = try ImageStore.saveValidated(data: png())
        let storage = NSTextStorage()
        let layout = HidingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        let view = TaskTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), textContainer: container)
        view.allowsUndo = true
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        view.insertImageTokens([ImageStore.token(id: id, width: 200)])
        let inserted = view.string
        XCTAssertEqual(ImageStore.tokens(in: inserted).count, 1)
        view.undoManager?.undo(); XCTAssertEqual(view.string, "")
        view.undoManager?.redo(); XCTAssertEqual(view.string, inserted)
        view.undoManager?.removeAllActions()
        _ = EditorStyleEngine.apply(to: view, ranges: [NSRange(location: 0, length: storage.length)],
            revealing: nil, ink: .textColor, size: 13.5, markdownEnabled: true,
            bodyFont: { NSFont.systemFont(ofSize: $0) }, isCompletedTask: { _ in false })
        let overlays = NoteImageOverlayManager(); view.imageOverlays = overlays
        overlays.attach(to: view, scrollView: scroll); overlays.refresh()
        let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? NoteImageOverlayView }.first)
        overlay.onSetWidthFraction(0.5)
        XCTAssertEqual(ImageStore.tokens(in: view.string).first?.width, 250)
        view.undoManager?.undo(); XCTAssertEqual(view.string, inserted)
        view.undoManager?.removeAllActions()
        overlays.refresh()
        let current = try XCTUnwrap(view.subviews.compactMap { $0 as? NoteImageOverlayView }.first)
        current.onApplyCrop(NSRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let croppedID = try XCTUnwrap(ImageStore.tokens(in: view.string).first?.id)
        XCTAssertNotEqual(croppedID, id)
        XCTAssertNotNil(ImageStore.data(id: croppedID))
        view.undoManager?.undo(); XCTAssertEqual(view.string, inserted)
        XCTAssertNotNil(ImageStore.data(id: id))
        view.undoManager?.redo()
        XCTAssertEqual(ImageStore.tokens(in: view.string).first?.id, croppedID)
    }
}
