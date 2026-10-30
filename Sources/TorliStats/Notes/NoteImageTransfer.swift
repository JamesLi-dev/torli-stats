import Foundation

/// Portable image archives and relative-file Markdown, independent of panels.
/// Imported assets always receive fresh IDs so a foreign archive cannot replace
/// an existing picture used by another note.
enum NoteImageTransfer {
    static func encodeArchive(_ notes: [Note]) throws -> Data {
        var archive = StickyArchive(notes: notes.map(StickyNote.init))
        var images: [String: String] = [:]
        var total = 0
        for id in Set(notes.flatMap { ImageStore.referencedIDs(in: $0.body) }).sorted() {
            guard let data = ImageStore.data(id: id) else { throw ImageAssetError.missingImage }
            _ = try ImageStore.validate(data)
            total += data.count
            guard total <= ImageStore.maximumArchiveBytes else { throw ImageAssetError.tooLarge }
            images[id] = data.base64EncodedString()
        }
        archive.images = images.isEmpty ? nil : images
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    static func decodeArchive(_ data: Data) throws -> [Note] {
        guard data.count <= ImageStore.maximumArchiveBytes * 2 else { throw ImageAssetError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(StickyArchive.self, from: data)
        guard (1...4).contains(archive.version) else { throw ImageAssetError.invalidArchive }
        guard archive.notes.allSatisfy({ NoteColor.all.indices.contains($0.color) }) else { throw PersistenceError.invalidColor }
        let notes = archive.notes.map(\.note)
        let required = Set(notes.flatMap { ImageStore.referencedIDs(in: $0.body) })
        var payloads: [String: Data] = [:]
        var total = 0
        // Validate everything before writing any files. Old text-only archives
        // have no assets and still follow this same path.
        for id in required {
            guard let encoded = archive.images?[id], let bytes = Data(base64Encoded: encoded) else { throw ImageAssetError.missingImage }
            _ = try ImageStore.validate(bytes)
            total += bytes.count
            guard total <= ImageStore.maximumArchiveBytes else { throw ImageAssetError.tooLarge }
            payloads[id] = bytes
        }
        var mapping: [String: String] = [:]
        do {
            for (id, bytes) in payloads { mapping[id] = try ImageStore.saveValidated(data: bytes) }
            return notes.map { note in
                var restored = note
                restored.body = replacingTokens(in: note.body) { token in
                    ImageStore.token(id: mapping[token.id] ?? token.id, width: token.width)
                }
                return restored
            }
        } catch {
            ImageStore.delete(ids: Array(mapping.values))
            throw error
        }
    }

    typealias Token = (id: String, width: CGFloat?, range: NSRange)
    static func replacingTokens(in body: String, replacement: (Token) throws -> String) rethrows -> String {
        var result = body as NSString
        for token in ImageStore.tokens(in: body).reversed() {
            result = result.replacingCharacters(in: token.range, with: try replacement(token)) as NSString
        }
        return result as String
    }

    /// A new asset folder per export avoids overwriting any previous export.
    /// Width rides in the alt text: ordinary Markdown readers render the image,
    /// and importing it back into Torli restores the editor's display width.
    static func exportMarkdown(_ body: String, directory: URL, assetFolder: String) throws -> String {
        guard assetFolder == (assetFolder as NSString).lastPathComponent,
              !["", ".", ".."].contains(assetFolder) else { throw ImageAssetError.invalidPath }
        let folder = directory.appendingPathComponent(assetFolder, isDirectory: true)
        return try replacingTokens(in: body) { token in
            guard let data = ImageStore.data(id: token.id) else { throw ImageAssetError.missingImage }
            let metadata = try ImageStore.validate(data)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = token.id + "." + metadata.ext
            let target = folder.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: target.path) {
                // No following or overwriting symlinks, even in an export folder.
                let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      try Data(contentsOf: target) == data else { throw ImageAssetError.invalidPath }
            } else {
                try data.write(to: target, options: .withoutOverwriting)
            }
            let alt = ImageStore.token(id: token.id, width: token.width).components(separatedBy: "](")[0] + "]"
            return alt + "(" + assetFolder + "/" + filename + ")"
        }
    }

    static func importMarkdown(_ body: String, relativeTo directory: URL) throws -> String {
        let regex = try NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(([^)\n]+)\)"#)
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var result = ns
        var imported: [String: String] = [:]
        do {
            for match in matches.reversed() {
                let raw = ns.substring(with: match.range(at: 2))
                // URL images are not fetched. Internal tokens belong in archives,
                // not portable Markdown; refusing them prevents accidental aliasing.
                if raw.hasPrefix("http://") || raw.hasPrefix("https://") { continue }
                guard let path = raw.removingPercentEncoding, !path.hasPrefix("/"),
                      URLComponents(string: path)?.scheme == nil else { throw ImageAssetError.invalidPath }
                let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else { throw ImageAssetError.invalidPath }
                let id: String
                if let existing = imported[file.path] { id = existing }
                else {
                    let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else { throw ImageAssetError.invalidImage }
                    guard let size = values.fileSize, size <= ImageStore.maximumBytes else { throw ImageAssetError.tooLarge }
                    id = try ImageStore.saveValidated(data: Data(contentsOf: file))
                    imported[file.path] = id
                }
                let alt = ns.substring(with: match.range(at: 1))
                let width = alt.hasPrefix("image|") ? Double(alt.dropFirst(6)).map { CGFloat($0) } : nil
                result = result.replacingCharacters(in: match.range, with: ImageStore.token(id: id, width: width)) as NSString
            }
            return result as String
        } catch {
            ImageStore.delete(ids: Array(imported.values))
            throw error
        }
    }
}
