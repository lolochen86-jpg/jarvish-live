import Foundation
import XCTest
import Darwin
@testable import JARVISHLive

final class NetworkInterfacesTests: XCTestCase {
    // Documentation-only address ranges are fixtures, never discovered devices.
    func testDecodesIPv4Sockaddr() {
        XCTAssertEqual(NetworkInterfaces.numericAddress(from: ipv4Data()), "192.0.2.37")
    }

    func testDecodesIPv6Sockaddr() {
        XCTAssertEqual(NetworkInterfaces.numericAddress(from: ipv6Data()), "2001:db8::1234")
    }

    func testRejectsEveryTruncatedIPv4Sockaddr() {
        let valid = ipv4Data()
        for count in 0..<valid.count {
            XCTAssertNil(NetworkInterfaces.numericAddress(from: Data(valid.prefix(count))), "Length \(count)")
        }
    }

    func testRejectsEveryTruncatedIPv6Sockaddr() {
        let valid = ipv6Data()
        for count in 0..<valid.count {
            XCTAssertNil(NetworkInterfaces.numericAddress(from: Data(valid.prefix(count))), "Length \(count)")
        }
    }

    func testRejectsMissingSocketLength() {
        var data = ipv4Data()
        data[0] = 0
        XCTAssertNil(NetworkInterfaces.numericAddress(from: data))
    }

    func testRejectsLengthSmallerThanAddressFamily() {
        var data = ipv6Data()
        data[0] = UInt8(MemoryLayout<sockaddr_in>.size)
        XCTAssertNil(NetworkInterfaces.numericAddress(from: data))
    }

    func testRejectsLengthBeyondAvailableBytes() {
        var data = ipv4Data()
        data[0] = UInt8(data.count + 1)
        XCTAssertNil(NetworkInterfaces.numericAddress(from: data))
    }

    func testRejectsUnsupportedSocketFamily() {
        var data = ipv4Data()
        data[1] = UInt8(AF_UNIX)
        XCTAssertNil(NetworkInterfaces.numericAddress(from: data))
    }

    func testRejectsLengthBeyondAlignedStorage() {
        var data = Data(repeating: 0, count: 255)
        data[0] = 255
        data[1] = UInt8(AF_INET)
        XCTAssertNil(NetworkInterfaces.numericAddress(from: data))
    }

    @MainActor
    func testCandidateServiceTypesMatchHostApplicationPlist() async throws {
        let configured = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String])
        let candidates = NetworkDiagnostics.candidateServiceTypes
        let normalize: (String) -> String = { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        XCTAssertEqual(Set(configured.map(normalize)), Set(candidates.map(normalize)))
        XCTAssertEqual(Set(candidates.map(normalize)), Set(["_http._tcp", "_https._tcp", "_rtsp._tcp"]))
        XCTAssertEqual(configured.count, candidates.count, "Do not hide duplicate or undeclared service types.")
        let explanation = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)
        XCTAssertFalse(explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    func testExportFailureCanBeRecordedAndClearedWithoutNetworkAccess() async {
        let model = NetworkDiagnostics()
        model.recordExportError(NSError(domain: "Fixture", code: 42,
                                       userInfo: [NSLocalizedDescriptionKey: "Synthetic export failure"]))
        XCTAssertEqual(model.log.entries.count, 1)
        XCTAssertEqual(model.log.entries.first?.level, .error)
        XCTAssertEqual(model.log.entries.first?.category, "Export")
        XCTAssertTrue(model.log.entries.first?.message.contains("Synthetic export failure") == true)
        model.clearLog()
        XCTAssertTrue(model.log.entries.isEmpty)
    }

    @MainActor
    func testStoppingAnIdleModelDoesNotCreateDiscoveryResults() async {
        let model = NetworkDiagnostics()
        model.stopDiscovery()
        model.stop()
        model.stop()
        XCTAssertFalse(model.isBrowsing)
        XCTAssertTrue(model.services.isEmpty)
        XCTAssertTrue(model.interfaces.isEmpty)
        XCTAssertTrue(model.log.entries.isEmpty)
    }

    private func ipv4Data(file: StaticString = #filePath, line: UInt = #line) -> Data {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(8080).bigEndian
        let result = "192.0.2.37".withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        XCTAssertEqual(result, 1, file: file, line: line)
        return Data(bytes: &address, count: MemoryLayout<sockaddr_in>.size)
    }

    private func ipv6Data(file: StaticString = #filePath, line: UInt = #line) -> Data {
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = in_port_t(8080).bigEndian
        let result = "2001:db8::1234".withCString { inet_pton(AF_INET6, $0, &address.sin6_addr) }
        XCTAssertEqual(result, 1, file: file, line: line)
        return Data(bytes: &address, count: MemoryLayout<sockaddr_in6>.size)
    }
}
