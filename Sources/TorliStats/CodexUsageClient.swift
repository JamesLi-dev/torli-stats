import Foundation

final class CodexUsageClient {
    private static let serverQueue = DispatchQueue(label: "local.torli.stats.codex.servers", qos: .utility)
    private let queue = DispatchQueue(label: "local.torli.stats.codex.client", qos: .utility)
    private let homePathProvider: () -> String?
    private let executableProvider: () -> URL?

    init(homePathProvider: @escaping () -> String?, executableProvider: @escaping () -> URL? = CodexUsageClient.executableURL) {
        self.homePathProvider = homePathProvider
        self.executableProvider = executableProvider
    }

    @discardableResult
    func fetch(preferLocal: Bool = true, completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void) -> CodexUsageRequest {
        let request = CodexUsageRequest(completion: completion)
        queue.async { [homePathProvider, executableProvider] in
            guard !request.isCancelled else { return }
            let validation = Self.validate(homePath: homePathProvider())
            guard validation.directoryExists else {
                request.complete(.failure(.codexHomeNotFound))
                return
            }
            guard validation.authFileExists else {
                request.complete(.failure(.authFileNotFound))
                return
            }
            let home = URL(fileURLWithPath: validation.resolvedPath)
            if preferLocal, let snapshot = CodexLocalUsageReader.snapshot(home: home) {
                request.complete(.success(snapshot))
                return
            }
            guard let executable = executableProvider() else {
                request.complete(.failure(.executableNotFound))
                return
            }

            Self.serverQueue.async {
                guard !request.isCancelled else { return }
                let completed = DispatchSemaphore(value: 0)
                let session = CodexServerSession(
                    executable: executable,
                    home: home,
                    completion: { result in
                        request.complete(result)
                        completed.signal()
                    }
                )
                guard request.attach(session) else { return }
                session.start()
                completed.wait()
                session.waitForExit()
            }
        }
        return request
    }

    static func validate(homePath: String?) -> CodexHomeValidation {
        let home = resolvedHomeURL(path: homePath)
        var isDirectory: ObjCBool = false
        let directoryExists = FileManager.default.fileExists(
            atPath: home.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let authFileExists = directoryExists && FileManager.default.fileExists(
            atPath: home.appendingPathComponent("auth.json").path
        )
        return CodexHomeValidation(
            resolvedPath: home.path,
            directoryExists: directoryExists,
            authFileExists: authFileExists,
            executablePath: executableURL()?.path
        )
    }

    private static func resolvedHomeURL(path: String?) -> URL {
        let rawPath: String
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawPath = path
        } else if let environmentPath = ProcessInfo.processInfo.environment["CODEX_HOME"], !environmentPath.isEmpty {
            rawPath = environmentPath
        } else {
            rawPath = "~/.codex"
        }
        let expanded = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static func executableURL() -> URL? {
        CodexCommandEnvironment().executableURL()
    }
}

final class CodexUsageRequest {
    private let lock = NSLock()
    private let completion: (Result<CodexUsageSnapshot, CodexUsageError>) -> Void
    private var session: CodexServerSession?
    private var cancelled = false
    private var completed = false

    init(completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void) {
        self.completion = completion
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        guard !cancelled, !completed else {
            lock.unlock()
            return
        }
        cancelled = true
        let session = session
        lock.unlock()
        session?.cancel()
    }

    func attach(_ session: CodexServerSession) -> Bool {
        lock.lock()
        guard !cancelled, !completed else {
            lock.unlock()
            session.cancel()
            return false
        }
        self.session = session
        lock.unlock()
        return true
    }

    func complete(_ result: Result<CodexUsageSnapshot, CodexUsageError>) {
        lock.lock()
        guard !cancelled, !completed else {
            lock.unlock()
            return
        }
        completed = true
        session = nil
        lock.unlock()
        completion(result)
    }
}

final class CodexServerSession {
    private let executable: URL
    private let home: URL
    private let completion: (Result<CodexUsageSnapshot, CodexUsageError>) -> Void
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let lock = NSLock()

    private var finished = false
    private var timeoutTimer: DispatchSourceTimer?
    private var accountResponse: [String: Any]?
    private var accountResponseReceived = false
    private var rateLimitsResponse: [String: Any]?
    private var requestIDsSent = false

    init(
        executable: URL,
        home: URL,
        completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void
    ) {
        self.executable = executable
        self.home = home
        self.completion = completion
    }

    func start() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        process.environment = CodexCommandEnvironment().environment(executable: executable, codexHome: home)

        // If app-server exits early, writing to its stdin would raise SIGPIPE
        // and terminate the whole app. Return EPIPE from the write instead.
        _ = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        do {
            try process.run()
        } catch {
            lock.unlock()
            finish(.failure(.processLaunchFailed))
            return
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        try? inputPipe.fileHandleForReading.close()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Drain stderr without exposing it to the UI or application logs.
            guard let self else { return }
            while !self.errorPipe.fileHandleForReading.availableData.isEmpty {}
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 15)
        timer.setEventHandler { [weak self] in
            self?.finish(.failure(.timeout))
        }
        timer.resume()
        timeoutTimer = timer
        lock.unlock()

        sendInitialize()
        DispatchQueue.global(qos: .utility).async {
            self.readResponses()
        }
    }

    func cancel() {
        finish(.failure(.processExited))
    }

    func waitForExit() {
        // The next account starts only after the previous server has shut down.
        if process.isRunning { process.waitUntilExit() }
    }

    private func sendInitialize() {
        sendRequest(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "torli-stats",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                ]
            ]
        )
    }

    private func sendAccountRequests() {
        guard !requestIDsSent else { return }
        requestIDsSent = true
        sendNotification(method: "initialized", params: [:])
        sendRequest(id: 2, method: "account/read", params: [:])
        sendRequest(id: 3, method: "account/rateLimits/read", params: [:])
    }

    private func sendRequest(id: Int, method: String, params: [String: Any]) {
        send([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ])
    }

    private func sendNotification(method: String, params: [String: Any]) {
        send([
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ])
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else {
            finish(.failure(.protocolError))
            return
        }
        line.append("\n")
        lock.lock()
        guard !finished else { lock.unlock(); return }
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(line.utf8))
            lock.unlock()
        } catch {
            lock.unlock()
            finish(.failure(.processExited))
        }
    }

    private func readResponses() {
        var buffer = Data()
        while !isFinished {
            let data = outputPipe.fileHandleForReading.availableData
            if data.isEmpty {
                if !isFinished {
                    finish(.failure(.processExited))
                }
                return
            }
            buffer.append(data)
            guard buffer.count <= 1024 * 1024 else { finish(.failure(.invalidResponse)); return }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                handle(line: Data(line))
            }
        }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }
        guard let id = CodexUsageParser.responseID(from: object["id"]) else { return }

        if let error = object["error"] as? [String: Any] {
            handleError(error, for: id)
            return
        }
        guard let result = object["result"] as? [String: Any] else {
            finish(.failure(.invalidResponse))
            return
        }

        switch id {
        case 1:
            sendAccountRequests()
        case 2:
            accountResponse = result["account"] as? [String: Any] ?? result
            accountResponseReceived = true
            finishIfReady()
        case 3:
            rateLimitsResponse = result
            finishIfReady()
        default:
            break
        }
    }

    private func handleError(_ error: [String: Any], for id: Int) {
        if CodexUsageParser.isUnauthorized(error) {
            finish(.failure(.unauthorized))
        } else if id == 2, (error["code"] as? NSNumber)?.intValue == -32601 {
            // Only an explicitly unsupported method is safe to ignore.
            accountResponseReceived = true
            finishIfReady()
        } else {
            finish(.failure(id == 1 ? .initializeFailed : .protocolError))
        }
    }

    private func finishIfReady() {
        guard accountResponseReceived, let rateLimitsResponse else { return }
        do {
            finish(.success(try CodexUsageParser.makeSnapshot(account: accountResponse, rateLimits: rateLimitsResponse)))
        } catch let error as CodexUsageError {
            finish(.failure(error))
        } catch {
            finish(.failure(.invalidResponse))
        }
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func finish(_ result: Result<CodexUsageSnapshot, CodexUsageError>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        timeoutTimer?.cancel()
        try? inputPipe.fileHandleForWriting.close()
        BoundedProcess.stop(process)
        completion(result)
    }
}
