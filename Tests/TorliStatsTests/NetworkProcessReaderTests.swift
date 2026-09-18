import XCTest
@testable import TorliStats

final class NetworkProcessReaderTests: XCTestCase {
    func testParserUsesLatestDeltaSampleAndGroupsHelperProcesses() {
        let output = """
        time,,interface,state,bytes_in,bytes_out
        12:00:00,Mock App.999999,,,400,100
        time,,interface,state,bytes_in,bytes_out
        12:00:01,Mock App.999999,,,120,40
        12:00:01,Mock App Helper.999998,,,80,10
        12:00:01,Other App.999997,,,25,5
        """

        let applications = NetworkProcessReader.parseDeltaSample(output)

        XCTAssertEqual(applications.count, 2)
        XCTAssertEqual(applications[0], NetworkApplicationRow(
            id: "mock app",
            name: "Mock App",
            download: 200,
            upload: 50
        ))
        XCTAssertEqual(applications[1], NetworkApplicationRow(
            id: "other app",
            name: "Other App",
            download: 25,
            upload: 5
        ))
    }

    func testParserOmitsInactiveApplications() {
        let output = """
        time,,interface,state,bytes_in,bytes_out
        12:00:01,Idle App.999996,,,0,0
        """

        XCTAssertTrue(NetworkProcessReader.parseDeltaSample(output).isEmpty)
    }
}
