import Security
import XCTest
import TorliStatsShared
@testable import TorliStats

final class SensorHelperDiagnosticsTests: XCTestCase {
    private func status(installed: Bool = true, signed: Bool = true, authorized: Bool = true) -> SensorHelperInstallationStatus {
        SensorHelperInstallationStatus(isInstalled: installed, signatureIsValid: signed,
                                       clientIsAuthorized: authorized, signatureMessage: "test")
    }

    func testMissingHelperDoesNotAskToRepairAnInstallation() {
        XCTAssertNil(status(installed: false, signed: false, authorized: false)
            .repairReason(isReachable: false, protocolVersion: nil, retriesRemaining: 0))
    }

    func testChangedAppAndInvalidHelperAreDetectedWithoutWaitingForXPC() {
        XCTAssertEqual(status(authorized: false).repairReason(isReachable: false, protocolVersion: nil, retriesRemaining: 3), .changedApp)
        XCTAssertEqual(status(signed: false).repairReason(isReachable: false, protocolVersion: nil, retriesRemaining: 3), .invalidSignature)
    }

    func testOldProtocolRequestsReinstallEvenWhenHelperResponds() {
        XCTAssertEqual(status().repairReason(isReachable: true, protocolVersion: SensorServiceConstants.protocolVersion - 1, retriesRemaining: 3), .incompatibleProtocol)
        XCTAssertEqual(status().repairReason(isReachable: true, protocolVersion: nil, retriesRemaining: 3), .incompatibleProtocol)
        XCTAssertEqual(status(authorized: false).repairReason(isReachable: true, protocolVersion: 1, retriesRemaining: 3), .incompatibleProtocol)
    }

    func testTransientConnectionFailureWaitsForRetriesAndRecoveryClearsWarning() {
        XCTAssertNil(status().repairReason(isReachable: false, protocolVersion: nil, retriesRemaining: 1))
        XCTAssertEqual(status().repairReason(isReachable: false, protocolVersion: nil, retriesRemaining: 0), .connectionUnavailable)
        XCTAssertNil(status().repairReason(isReachable: true, protocolVersion: SensorServiceConstants.protocolVersion, retriesRemaining: 0))
    }

    func testCurrentSignatureMatchesOwnRequirementButRejectsAnotherApp() throws {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        var staticCode: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(code), [], &staticCode), errSecSuccess)
        var requirement: SecRequirement?
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(staticCode), [], &requirement), errSecSuccess)
        var text: CFString?
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(requirement), [], &text), errSecSuccess)
        XCTAssertTrue(SensorHelperInstallationStatus.currentProcessMatches(try XCTUnwrap(text) as String))
        XCTAssertFalse(SensorHelperInstallationStatus.currentProcessMatches("identifier \"local.torli.nonexistent-test-app\""))
        XCTAssertFalse(SensorHelperInstallationStatus.currentProcessMatches("not a valid signing requirement"))
    }
}
