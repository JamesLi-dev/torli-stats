import XCTest
@testable import TorliStats

final class CodexCommandEnvironmentTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("codex command ' " + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    private func resolver(_ environment: [String: String] = ["PATH": "/usr/bin:/bin"]) -> CodexCommandEnvironment {
        CodexCommandEnvironment(inherited: environment, userHome: home, systemPaths: ["/usr/bin", "/bin"])
    }

    @discardableResult
    private func executable(_ relativePath: String, content: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        let file = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    func testFinderPathDiscoversBunAndNPMGlobalInstallations() throws {
        let bun = try executable(".bun/bin/codex")
        XCTAssertEqual(resolver().executableURL(), bun)
        try FileManager.default.removeItem(at: bun)
        let npm = try executable(".npm-global/bin/codex")
        XCTAssertEqual(resolver().executableURL(), npm)
    }

    func testExplicitPATHWinsOverFallbacks() throws {
        let preferred = try executable("custom/bin/codex")
        try executable(".bun/bin/codex")
        XCTAssertEqual(resolver(["PATH": preferred.deletingLastPathComponent().path]).executableURL(), preferred)
    }

    func testNPMConfiguredPrefixSupportsHomeAndSpaces() throws {
        let cli = try executable("npm packages/bin/codex")
        try "# config\n//registry.npmjs.org/:_authToken=test-placeholder\nprefix=\"${HOME}/npm packages\"\n"
            .write(to: home.appendingPathComponent(".npmrc"), atomically: true, encoding: .utf8)
        XCTAssertEqual(resolver().executableURL(), cli)
    }

    func testNVMDefaultAliasWinsOverNewerVersion() throws {
        let preferred = try executable(".nvm/versions/node/v22.12.0/bin/codex")
        try executable(".nvm/versions/node/v24.0.0/bin/codex")
        let alias = home.appendingPathComponent(".nvm/alias/lts")
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
        try "lts/*\n".write(to: alias.deletingLastPathComponent().appendingPathComponent("default"), atomically: true, encoding: .utf8)
        try "22\n".write(to: alias.appendingPathComponent("*"), atomically: true, encoding: .utf8)
        XCTAssertEqual(resolver().executableURL(), preferred)
    }

    func testCustomNVMDirectoryUsesNumericVersionOrderAndSkipsMissingCLI() throws {
        try executable("custom-nvm/versions/node/v9.0.0/bin/codex")
        let expected = try executable("custom-nvm/versions/node/v22.0.0/bin/codex")
        try executable("custom-nvm/versions/node/v24.0.0/bin/node")
        XCTAssertEqual(resolver(["NVM_DIR": home.appendingPathComponent("custom-nvm").path]).executableURL(), expected)
    }

    func testChildPreservesProxyAndCertificateEnvironmentButUsesSelectedAccount() throws {
        let cli = try executable(".bun/bin/codex")
        let inherited = ["PATH": "/usr/bin:/bin", "HOME": home.path,
                         "HTTPS_PROXY": "http://127.0.0.1:7890", "ALL_PROXY": "socks5://127.0.0.1:7891",
                         "http_proxy": "http://127.0.0.1:7890", "NO_PROXY": "localhost",
                         "NODE_EXTRA_CA_CERTS": "/test/ca.pem", "LANG": "en_US.UTF-8", "CODEX_HOME": "/old/account"]
        let account = home.appendingPathComponent("second account")
        let actual = resolver(inherited).environment(executable: cli, codexHome: account)
        for (key, value) in inherited where key != "PATH" && key != "CODEX_HOME" {
            XCTAssertEqual(actual[key], value, key)
        }
        XCTAssertEqual(actual["CODEX_HOME"], account.path)
        XCTAssertEqual(actual["PATH"]?.split(separator: ":").first.map(String.init), cli.deletingLastPathComponent().path)
    }

    func testSymlinkedNPMCLIStartsItsNodeRuntimeWithFinderEnvironment() throws {
        let packageCLI = try executable(".nvm/versions/node/v22.0.0/lib/node_modules/@openai/codex/bin/codex.js", content: "#!/usr/bin/env node\n")
        try executable(".nvm/versions/node/v22.0.0/bin/node", content: "#!/bin/sh\nprintf '%s\\n' \"$CODEX_HOME\" \"$HTTPS_PROXY\"\n")
        let localBin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        let shim = localBin.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: shim, withDestinationURL: packageCLI)
        let environment = resolver(["PATH": "/usr/bin:/bin", "HTTPS_PROXY": "http://127.0.0.1:7890"])
        let found = try XCTUnwrap(environment.executableURL())
        XCTAssertEqual(found, shim)
        let account = home.appendingPathComponent("account with spaces")
        let process = Process()
        process.executableURL = found
        process.environment = environment.environment(executable: found, codexHome: account)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: output, encoding: .utf8), account.path + "\nhttp://127.0.0.1:7890\n")
    }

    func testNonExecutableAndRelativePATHEntriesAreIgnored() throws {
        let cli = try executable(".bun/bin/codex")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cli.path)
        XCTAssertNil(resolver(["PATH": ":.:relative/bin"]).executableURL())
    }
}
