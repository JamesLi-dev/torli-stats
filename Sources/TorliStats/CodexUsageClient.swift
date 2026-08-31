import Foundation

final class CodexUsageClient {
    private let queue = DispatchQueue(label: "local.torli.stats.codex.client", qos: .utility)
    private let homePathProvider: () -> String?

    init(homePathProvider: @escaping () -> String?) {
        self.homePathProvider = homePathProvider
    }

    func fetch(completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void) {
        queue.async { [homePathProvider] in
            let validation = Self.validate(homePath: homePathProvider())
            guard validation.directoryExists else {
                completion(.failure(.codexHomeNotFound))
                return
            }
            guard validation.authFileExists else {
                completion(.failure(.authFileNotFound))
                return
            }
            guard let executablePath = validation.executablePath else {
                completion(.failure(.executableNotFound))
                return
            }

            CodexServerSession(
                executable: URL(fileURLWithPath: executablePath),
                home: URL(fileURLWithPath: validation.resolvedPath),
                completion: completion
            ).start()
        }
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
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { String($0) + "/codex" }
        }
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

private final class CodexServerSession {
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
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment: [String: String] = [:]
        let inherited = ProcessInfo.processInfo.environment
        environment["PATH"] = inherited["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["HOME"] = inherited["HOME"] ?? NSHomeDirectory()
        environment["CODEX_HOME"] = home.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            finish(.failure(.processLaunchFailed))
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Drain stderr without exposing it to the UI or application logs.
            _ = self?.errorPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 15)
        timer.setEventHandler { [weak self] in
            self?.finish(.failure(.timeout))
        }
        timer.resume()
        timeoutTimer = timer

        sendInitialize()
        DispatchQueue.global(qos: .utility).async {
            self.readResponses()
        }
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
        guard !isFinished else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else {
            finish(.failure(.protocolError))
            return
        }
        line.append("\n")
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        } catch {
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
        guard let id = responseID(from: object["id"]) else { return }

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
        if id == 2 {
            // Older app-server versions may not expose account/read. The rate
            // limits response remains sufficient for a generic "C" label.
            accountResponseReceived = true
            finishIfReady()
            return
        }
        if id == 3 {
            let code = (error["code"] as? NSNumber)?.intValue
            if code == 401 || code == 403 {
                finish(.failure(.unauthorized))
            } else {
                finish(.failure(.protocolError))
            }
            return
        }
        finish(.failure(id == 1 ? .initializeFailed : .protocolError))
    }

    private func finishIfReady() {
        guard accountResponseReceived, let rateLimitsResponse else { return }
        do {
            finish(.success(try makeSnapshot(account: accountResponse, rateLimits: rateLimitsResponse)))
        } catch let error as CodexUsageError {
            finish(.failure(error))
        } catch {
            finish(.failure(.invalidResponse))
        }
    }

    private func makeSnapshot(account: [String: Any]?, rateLimits: [String: Any]) throws -> CodexUsageSnapshot {
        let accountObject = account?["account"] as? [String: Any] ?? account ?? [:]
        let email = accountObject["email"] as? String
        let planType = (accountObject["planType"] as? String)
            ?? (rateLimits["rateLimits"] as? [String: Any])?["planType"] as? String
        let rateLimitsObject = rateLimits["rateLimits"] as? [String: Any] ?? rateLimits
        guard let primaryObject = rateLimitsObject["primary"] as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }
        guard let primary = parseWindow(primaryObject) else {
            throw CodexUsageError.invalidResponse
        }

        let secondary = (rateLimitsObject["secondary"] as? [String: Any]).flatMap(parseWindow)
        let credits = parseCredits(rateLimitsObject["credits"])
        let prefix = Self.displayPrefix(for: email)
        let identity = CodexAccountIdentity(email: email, displayPrefix: prefix, planType: planType)

        return CodexUsageSnapshot(
            account: identity,
            primary: primary,
            secondary: secondary,
            credits: credits,
            rateLimitReachedType: rateLimitsObject["rateLimitReachedType"] as? String,
            fetchedAt: Date()
        )
    }

    private func parseWindow(_ object: [String: Any]) -> CodexUsageWindow? {
        guard let usedPercent = number(object["usedPercent"]) else { return nil }
        let duration = number(object["windowDurationMins"]).map { Int($0) }
        let resetsAt = number(object["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return CodexUsageWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowDurationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    private func parseCredits(_ value: Any?) -> CodexCredits? {
        guard let object = value as? [String: Any] else { return nil }
        let hasCredits = object["hasCredits"] as? Bool ?? false
        let unlimited = object["unlimited"] as? Bool ?? false
        let balance: String?
        if let string = object["balance"] as? String {
            balance = string
        } else if let number = object["balance"] as? NSNumber {
            balance = number.stringValue
        } else {
            balance = nil
        }
        return CodexCredits(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func displayPrefix(for email: String?) -> String {
        guard let email,
              let localPart = email.split(separator: "@", maxSplits: 1).first,
              !localPart.isEmpty else {
            return "C"
        }
        let prefix = String(localPart.prefix(3)).uppercased()
        return prefix.isEmpty ? "C" : prefix
    }

    private func responseID(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
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
        if process.isRunning {
            process.terminate()
        }
        completion(result)
    }
}
