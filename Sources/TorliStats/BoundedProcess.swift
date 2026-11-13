import Foundation
import Darwin

enum BoundedProcess {
    /// For background collectors only. Nonblocking reads bound both output and
    /// wall time, even if a descendant keeps stdout open after its parent exits.
    static func output(_ executable: String, arguments: [String], timeout: TimeInterval = 5,
                       maximumBytes: Int = 8 * 1024 * 1024) -> Data? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { return nil }
        do { try process.run() } catch { return nil }
        try? pipe.fileHandleForWriting.close()
        defer { try? pipe.fileHandleForReading.close() }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        var data = Data(), bytes = [UInt8](repeating: 0, count: 16 * 1024)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let count = read(fd, &bytes, bytes.count)
            if count > 0 {
                guard data.count + count <= maximumBytes else { stop(process); return nil }
                data.append(contentsOf: bytes.prefix(count))
            } else if !process.isRunning {
                return process.terminationStatus == 0 ? data : nil
            } else if count < 0 && errno != EAGAIN && errno != EINTR {
                stop(process)
                return nil
            } else {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                _ = poll(&descriptor, 1, 20)
            }
        }
        stop(process)
        return nil
    }

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
