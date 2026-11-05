import XCTest
import Security
@testable import TorliStats

@MainActor
final class WakaTimeCredentialTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let name = "WakaTimeCredentialTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testHintIsNonSecretAndStartsUnknown() throws {
        let (settings, name) = defaults()
        defer { settings.removePersistentDomain(forName: name) }
        XCTAssertEqual(WakaTimeCredentialHint.load(from: settings), .unknown)
        let token = "synthetic-token"
        XCTAssertEqual(try WakaTimeKeychain.readOAuthToken(read: { Data(token.utf8) }, defaults: settings), token)
        XCTAssertEqual(WakaTimeCredentialHint.load(from: settings), .configured)
        XCTAssertEqual(settings.string(forKey: WakaTimeCredentialHint.defaultsKey), "configured")
        XCTAssertFalse(String(describing: settings.persistentDomain(forName: name)).contains(token))
    }

    func testMissingAndTombstoneAreNotConfigured() throws {
        let (settings, name) = defaults()
        defer { settings.removePersistentDomain(forName: name) }
        for data: Data? in [nil, Data()] {
            WakaTimeCredentialHint.configured.save(to: settings)
            XCTAssertNil(try WakaTimeKeychain.readOAuthToken(read: { data }, defaults: settings))
            XCTAssertEqual(WakaTimeCredentialHint.load(from: settings), .notConfigured)
        }
    }

    func testDeniedCancelledAndMalformedPreserveConfigurationHint() {
        let (settings, name) = defaults()
        defer { settings.removePersistentDomain(forName: name) }
        WakaTimeCredentialHint.configured.save(to: settings)
        for status in [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecNotAvailable] {
            XCTAssertThrowsError(try WakaTimeKeychain.readOAuthToken(read: {
                throw CredentialVaultError.unavailable(status)
            }, defaults: settings))
            XCTAssertEqual(WakaTimeCredentialHint.load(from: settings), .configured)
        }
        for data in [Data([0xFF]), Data("invalid token".utf8)] {
            XCTAssertThrowsError(try WakaTimeKeychain.readOAuthToken(read: { data }, defaults: settings))
            XCTAssertEqual(WakaTimeCredentialHint.load(from: settings), .configured)
        }
    }

    func testConstructionAndDisabledSynchronizationNeverReadCredentials() {
        var reads = 0
        let store = WakaTimeUsageStore(apiKeyProvider: { reads += 1; return nil }, rangeProvider: { .last30Days })
        XCTAssertEqual(reads, 0)
        store.synchronize(isEnabled: false)
        XCTAssertEqual(reads, 0)
        store.refresh()
        XCTAssertEqual(reads, 0)
    }

    func testFailuresRemainUnavailableInsteadOfNotConfigured() {
        for error: Error in [CredentialVaultError.unavailable(errSecUserCanceled), CredentialVaultError.malformed, CredentialVaultError.unavailable(errSecNotAvailable)] {
            let requests = WakaTimeUsageStore.Requests(
                snapshot: { _, _, _ in XCTFail("No network request on credential failure") },
                today: { _, _, _ in XCTFail("No network request on credential failure") },
                period: { _, _, _, _ in XCTFail("No network request on credential failure") }
            )
            let store = WakaTimeUsageStore(apiKeyProvider: { throw error }, rangeProvider: { .last30Days }, requests: requests)
            store.synchronize(isEnabled: true)
            guard case .unavailable(let message, _) = store.state else { XCTFail("Must not report unconfigured"); continue }
            XCTAssertEqual(message, WakaTimeCredentialFailure.message(for: error))
            store.refresh()
            guard case .unavailable = store.state else { XCTFail("Manual failure must stay visible"); continue }
        }
        XCTAssertNotEqual(WakaTimeCredentialFailure.message(for: CredentialVaultError.malformed), WakaTimeCredentialFailure.message(for: CredentialVaultError.unavailable(errSecUserCanceled)))
    }

    func testBackgroundNeverUsesInteractiveProviderAndManualRefreshCanRecover() {
        var granted = false
        var interactiveReads = 0
        var requestsMade = 0
        let requests = WakaTimeUsageStore.Requests(today: { token, _, _ in
            XCTAssertEqual(token, "synthetic")
            requestsMade += 1
        })
        let store = WakaTimeUsageStore(apiKeyProvider: {
            if !granted { throw CredentialVaultError.unavailable(errSecInteractionNotAllowed) }
            return "synthetic"
        }, interactiveCredentialProvider: {
            interactiveReads += 1
            granted = true
            return "synthetic"
        }, rangeProvider: { .last30Days }, requests: requests)
        store.synchronize(isEnabled: true)
        store.refresh(allowCredentialInteraction: false)
        XCTAssertEqual(interactiveReads, 0)
        XCTAssertEqual(requestsMade, 0)
        store.refresh()
        XCTAssertEqual(interactiveReads, 1)
        XCTAssertEqual(requestsMade, 1)
        guard case .loading = store.state else { return XCTFail("Manual refresh should recover") }
        store.synchronize(isEnabled: false)
    }

    func testActualMissingCredentialDoesNotRequestNetwork() {
        let store = WakaTimeUsageStore(apiKeyProvider: { nil }, rangeProvider: { .last30Days }, requests: .init(today: { _, _, _ in XCTFail("Missing token") }))
        store.synchronize(isEnabled: true)
        store.refresh()
        guard case .notConfigured = store.state else { return XCTFail("A genuine absence should be not configured") }
    }
}
