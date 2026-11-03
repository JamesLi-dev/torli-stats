import Foundation
import Security

protocol CredentialVaultBackend {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

enum CredentialVaultError: Error { case unavailable(OSStatus), malformed }

private struct KeychainCredentialVaultBackend: CredentialVaultBackend {
    let service: String
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialVaultError.unavailable(status) }
        guard let data = result as? Data else { throw CredentialVaultError.malformed }
        return data
    }
    func write(_ data: Data) throws {
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialVaultError.unavailable(status) }
    }
}

/// One login-Keychain permission for all features. TOTP supplies only an
/// enclave-encrypted payload; this container never receives its plaintext.
/// Serialize namespace updates so concurrent mail / WakaTime writes cannot
/// overwrite one another. No credentials are cached here.
public final class SharedCredentialVault {
    public static let shared = SharedCredentialVault()
    private static let lock = NSRecursiveLock()
    private let backend: CredentialVaultBackend
    private struct Payload: Codable { let version: Int; var entries: [String: Data] }
    public init(service: String = "local.torli.stats.credentials.v1", account: String = "shared-vault") {
        backend = KeychainCredentialVaultBackend(service: service, account: account)
    }
    init(backend: CredentialVaultBackend) { self.backend = backend }
    private func load() throws -> Payload {
        guard let data = try backend.read() else { return Payload(version: 1, entries: [:]) }
        guard data.count <= 16_777_216,
              let value = try? JSONDecoder().decode(Payload.self, from: data),
              value.version == 1, value.entries.count <= 32 else { throw CredentialVaultError.malformed }
        return value
    }
    /// Legacy data is read only when the namespace has never been written.
    /// Access denial / corruption must not be interpreted as an empty vault.
    public func read(_ namespace: String, migrating legacy: () throws -> Data? = { nil }) throws -> Data? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var value = try load()
        if let data = value.entries[namespace] { return data }
        guard let data = try legacy() else { return nil }
        value.entries[namespace] = data
        try persist(value)
        return data
    }
    public func write(_ data: Data, for namespace: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var value = try load(); value.entries[namespace] = data
        try persist(value)
    }
    private func persist(_ value: Payload) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16_777_216, value.entries.count <= 32 else { throw CredentialVaultError.malformed }
        try backend.write(data)
        guard try backend.read() == data else { throw CredentialVaultError.malformed }
    }
}
