import Foundation
import CZstd

/// Decodes in bounded chunks without extracting conversation files to disk.
/// A changed compressed source is reread from its first frame.
final class ZstdFileReader {
    private let handle: FileHandle
    private let context: OpaquePointer
    private var input = Data()
    private var position = 0
    private var remaining = 1
    private var reachedEOF = false
    private var finished = false

    init(url: URL) throws {
        guard let context = ZSTD_createDStream() else { throw CocoaError(.fileReadUnknown) }
        do {
            // Bound memory even when a damaged frame declares a very large window.
            guard ZSTD_isError(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, 27)) == 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            ZSTD_freeDStream(context)
            throw error
        }
        self.context = context
    }

    deinit {
        try? handle.close()
        ZSTD_freeDStream(context)
    }

    func read() throws -> Data? {
        if finished { return nil }
        var output = Data(count: 256 * 1024)
        while true {
            if position == input.count && !reachedEOF {
                input = try handle.read(upToCount: 128 * 1024) ?? Data()
                position = 0
                reachedEOF = input.isEmpty
            }
            if reachedEOF && remaining == 0 {
                finished = true
                return nil
            }
            var produced = 0
            let result = input.withUnsafeBytes { source in
                output.withUnsafeMutableBytes { destination in
                    var sourceBuffer = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: position)
                    var destinationBuffer = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                    let result = ZSTD_decompressStream(context, &destinationBuffer, &sourceBuffer)
                    position = sourceBuffer.pos
                    produced = destinationBuffer.pos
                    return result
                }
            }
            guard ZSTD_isError(result) == 0 else { throw CocoaError(.fileReadCorruptFile) }
            guard !reachedEOF || produced > 0 || result == 0 else { throw CocoaError(.fileReadCorruptFile) }
            remaining = result
            if produced > 0 {
                output.count = produced
                return output
            }
        }
    }
}
