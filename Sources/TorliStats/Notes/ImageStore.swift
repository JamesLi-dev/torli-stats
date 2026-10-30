import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageAssetError: LocalizedError {
    case invalidImage, tooLarge, missingImage, invalidArchive, invalidPath
    var errorDescription: String? {
        switch self {
        case .invalidImage: return NotesL10n.text("image.error.invalid")
        case .tooLarge: return NotesL10n.text("image.error.size")
        case .missingImage: return NotesL10n.text("image.error.missing")
        case .invalidArchive: return NotesL10n.text("image.error.archive")
        case .invalidPath: return NotesL10n.text("image.error.path")
        }
    }
}

/// Original PNG/JPEG bytes stay local in TorliStats/Notes/Images. Display widths
/// live in the encrypted body; cached previews never replace original assets.
enum ImageStore {
    static let scheme = "torli-img"
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumPixels = 40_000_000
    static let maximumArchiveBytes = 200 * 1024 * 1024
    // Test fixtures use a separate directory and never touch live attachments.
    static var directoryOverride: URL? { didSet { cache.removeAllObjects() } }
    static var directory: URL { directoryOverride ?? Paths.support.appendingPathComponent("Images", isDirectory: true) }
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 24
        return cache
    }()

    struct Metadata {
        let ext: String
        let width: Int
        let height: Int
        let orientation: Int
        var size: NSSize {
            (5...8).contains(orientation) ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
        }
    }

    static func validate(_ data: Data) throws -> Metadata {
        guard data.count <= maximumBytes else { throw ImageAssetError.tooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int,
              let height = info[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageAssetError.invalidImage }
        guard width <= maximumPixels / height else { throw ImageAssetError.tooLarge }
        return Metadata(ext: type == UTType.jpeg.identifier ? "jpg" : "png", width: width, height: height,
                        orientation: info[kCGImagePropertyOrientation] as? Int ?? 1)
    }

    static func report(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NotesL10n.text("image.error.title")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    static func save(image: NSImage) -> String? {
        do {
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { throw ImageAssetError.invalidImage }
            guard bitmap.pixelsWide <= maximumPixels / bitmap.pixelsHigh else { throw ImageAssetError.tooLarge }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ImageAssetError.invalidImage }
            return try saveValidated(data: png)
        } catch { report(error); return nil }
    }

    static func save(data: Data, ext: String) -> String? {
        do { return try saveValidated(data: data) }
        catch { report(error); return nil }
    }

    @discardableResult
    static func saveValidated(data: Data) throws -> String {
        let metadata = try validate(data)
        // Force a bounded decode before accepting malformed/truncated payloads.
        guard decoded(data, maxSide: 64) != nil else { throw ImageAssetError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString
        let url = directory.appendingPathComponent(id + "." + metadata.ext)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return id
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
        }
    }

    static func fileURL(id: String) -> URL? {
        guard validID(id) else { return nil }
        for ext in ["png", "jpg", "jpeg"] {
            let url = directory.appendingPathComponent(id + "." + ext)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            return url
        }
        return nil
    }

    static func data(id: String) -> Data? {
        guard let url = fileURL(id: id),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func decoded(_ data: Data, maxSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    static func image(id: String) -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let data = data(id: id), let metadata = try? validate(data),
              let cg = decoded(data, maxSide: 1600) else { return nil }
        let image = NSImage(cgImage: cg, size: metadata.size)
        cache.setObject(image, forKey: id as NSString, cost: cg.bytesPerRow * cg.height)
        return image
    }

    static func crop(id: String, aspectRatio: CGFloat) -> String? {
        guard aspectRatio.isFinite, aspectRatio > 0, let data = data(id: id),
              let metadata = try? validate(data) else { return nil }
        let size = metadata.size
        let ratio = size.width / size.height
        let w = min(1, aspectRatio / ratio)
        let h = min(1, ratio / aspectRatio)
        return crop(id: id, normalizedRect: NSRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h))
    }

    /// Coordinates are normalized from the top left. Each crop is a new file:
    /// Undo only restores the old token and the original is never overwritten.
    static func crop(id: String, normalizedRect: NSRect) -> String? {
        do {
            guard [normalizedRect.origin.x, normalizedRect.origin.y, normalizedRect.width, normalizedRect.height].allSatisfy(\.isFinite),
                  normalizedRect.width > 0, normalizedRect.height > 0,
                  let data = data(id: id) else { throw ImageAssetError.invalidImage }
            let metadata = try validate(data)
            guard let source = decoded(data, maxSide: max(metadata.width, metadata.height)) else { throw ImageAssetError.invalidImage }
            let normalized = normalizedRect.intersection(NSRect(x: 0, y: 0, width: 1, height: 1))
            guard !normalized.isEmpty else { throw ImageAssetError.invalidImage }
            let rect = CGRect(x: floor(normalized.minX * CGFloat(source.width)),
                              y: floor(normalized.minY * CGFloat(source.height)),
                              width: max(1, floor(normalized.width * CGFloat(source.width))),
                              height: max(1, floor(normalized.height * CGFloat(source.height))))
            guard let cropped = source.cropping(to: rect),
                  let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else { throw ImageAssetError.invalidImage }
            return try saveValidated(data: png)
        } catch { report(error); return nil }
    }

    static func delete(ids: [String]) {
        for id in ids {
            cache.removeObject(forKey: id as NSString)
            if let url = fileURL(id: id) { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func allIDs() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url in
            let id = url.deletingPathExtension().lastPathComponent
            return fileURL(id: id) != nil ? id : nil
        }
    }

    /// Only called after a successful startup load, before editors acquire undo
    /// histories. Never collect images during editing or a failed database load.
    static func removeOrphans(referencedBy notes: [Note]) {
        let used = Set(notes.flatMap { referencedIDs(in: $0.body) })
        delete(ids: allIDs().filter { !used.contains($0) })
    }

    // MARK: - Tokens

    /// The full markdown token line (no trailing newline). Integral widths are
    /// written without decimals so the note text stays tidy.
    static func token(id: String, width: CGFloat?) -> String {
        guard let w = width, w.isFinite, w > 0, w <= 100_000 else { return "![image](\(scheme)://\(id))" }
        let s: String
        if w.rounded() == w {
            s = String(Int(w))
        } else {
            s = String(format: "%.1f", Double(w))
        }
        return "![image|\(s)](\(scheme)://\(id))"
    }

    /// One shared regex; tokens are matched over the text as NSString so the
    /// reported NSRanges line up with NSTextStorage indexing.
    private static let tokenRegex: NSRegularExpression = {
        // width group first, id group second
        let pattern = "!\\[image(?:\\|([0-9]+(?:\\.[0-9]+)?))?\\]\\((?:torli-img|noty-img)://([A-Za-z0-9-]+)\\)"
        // try! is safe: the pattern is a compile-time constant.
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func tokens(in text: String) -> [(id: String, width: CGFloat?, range: NSRange)] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return tokenRegex.matches(in: text, range: full).map { m in
            var width: CGFloat?
            let wr = m.range(at: 1)
            if wr.location != NSNotFound { width = CGFloat(Double(ns.substring(with: wr)) ?? 0) }
            return (id: ns.substring(with: m.range(at: 2)), width: width, range: m.range)
        }
    }

    static func referencedIDs(in text: String) -> [String] {
        tokens(in: text).map(\.id)
    }

}
