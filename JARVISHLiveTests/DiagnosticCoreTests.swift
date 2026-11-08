import XCTest
@testable import JARVISHLive

final class DiagnosticCoreTests: XCTestCase {
    func testReportedPhoneAddressOnlyEstablishesSubnetMembership() throws {
        // This is a user-provided test fixture, not an app default or a
        // discovered helmet endpoint. Membership cannot prove reachability.
        let subnet = try IPv4Subnet(address: "192.168.1.11", mask: "255.255.255.0")
        XCTAssertEqual(subnet.address, "192.168.1.11")
        XCTAssertEqual(subnet.mask, "255.255.255.0")
        XCTAssertEqual(subnet.prefixLength, 24)
        XCTAssertEqual(subnet.networkAddress, "192.168.1.0")
        XCTAssertEqual(subnet.broadcastAddress, "192.168.1.255")
        XCTAssertTrue(subnet.contains("192.168.1.1"))
        XCTAssertTrue(subnet.contains("192.168.1.10"))
        XCTAssertTrue(subnet.contains("192.168.1.100"))
        XCTAssertFalse(subnet.contains("192.168.2.11"))
        // There is deliberately no inferred router, helmet, or stream URL.
    }

    func testNonOctetAlignedSubnet() throws {
        let subnet = try IPv4Subnet(address: "10.17.201.250", mask: "255.255.248.0")
        XCTAssertEqual(subnet.prefixLength, 21)
        XCTAssertEqual(subnet.networkAddress, "10.17.200.0")
        XCTAssertEqual(subnet.broadcastAddress, "10.17.207.255")
        XCTAssertTrue(subnet.contains("10.17.207.255"))
        XCTAssertFalse(subnet.contains("10.17.208.0"))
    }

    func testZeroPrefixIncludesEntireIPv4RangeWithoutOverflow() throws {
        let subnet = try IPv4Subnet(address: "203.0.113.42", mask: "0.0.0.0")
        XCTAssertEqual(subnet.prefixLength, 0)
        XCTAssertEqual(subnet.networkAddress, "0.0.0.0")
        XCTAssertEqual(subnet.broadcastAddress, "255.255.255.255")
        XCTAssertTrue(subnet.contains("0.0.0.0"))
        XCTAssertTrue(subnet.contains("255.255.255.255"))
    }

    func test31PrefixContainsExactlyTwoAddresses() throws {
        let subnet = try IPv4Subnet(address: "198.51.100.11", mask: "255.255.255.254")
        XCTAssertEqual(subnet.prefixLength, 31)
        XCTAssertEqual(subnet.networkAddress, "198.51.100.10")
        XCTAssertEqual(subnet.broadcastAddress, "198.51.100.11")
        XCTAssertTrue(subnet.contains("198.51.100.10"))
        XCTAssertTrue(subnet.contains("198.51.100.11"))
        XCTAssertFalse(subnet.contains("198.51.100.9"))
        XCTAssertFalse(subnet.contains("198.51.100.12"))
    }

    func test32PrefixContainsOnlyInterfaceAddress() throws {
        let subnet = try IPv4Subnet(address: "203.0.113.255", mask: "255.255.255.255")
        XCTAssertEqual(subnet.prefixLength, 32)
        XCTAssertEqual(subnet.networkAddress, "203.0.113.255")
        XCTAssertEqual(subnet.broadcastAddress, "203.0.113.255")
        XCTAssertTrue(subnet.contains("203.0.113.255"))
        XCTAssertFalse(subnet.contains("203.0.113.254"))
    }

    func testMalformedAddressesAreRejected() {
        let inputs = ["", "192.168.1", "192.168.1.1.1", "192.168..1", "256.1.1.1",
                      "-1.1.1.1", "+1.1.1.1", "192.168.001.1", " 192.168.1.1",
                      "192.168.1.1\n", "１.2.3.4", "::1", "0xC0.168.1.1"]
        for address in inputs {
            XCTAssertThrowsError(try IPv4Subnet(address: address, mask: "255.255.255.0"), address) {
                XCTAssertEqual($0 as? IPv4Subnet.ValidationError, .invalidAddress)
            }
        }
    }

    func testMalformedAndNoncontiguousMasksAreRejected() {
        XCTAssertThrowsError(try IPv4Subnet(address: "192.0.2.1", mask: "255.255.256.0")) {
            XCTAssertEqual($0 as? IPv4Subnet.ValidationError, .invalidMask)
        }
        for mask in ["255.0.255.0", "255.255.255.1", "127.255.255.255", "0.0.0.1"] {
            XCTAssertThrowsError(try IPv4Subnet(address: "192.0.2.1", mask: mask), mask) {
                XCTAssertEqual($0 as? IPv4Subnet.ValidationError, .nonContiguousMask)
            }
        }
    }

    func testAllContiguousPrefixesAreAccepted() throws {
        for prefix in 0...32 {
            let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
            let string = [24, 16, 8, 0].map { String((mask >> $0) & 255) }.joined(separator: ".")
            let subnet = try IPv4Subnet(address: "192.0.2.3", mask: string)
            XCTAssertEqual(subnet.prefixLength, prefix)
            XCTAssertTrue(subnet.contains("192.0.2.3"))
        }
    }

    func testContainsRejectsInvalidInputEvenWithZeroPrefix() throws {
        let subnet = try IPv4Subnet(address: "0.0.0.0", mask: "0.0.0.0")
        XCTAssertFalse(subnet.contains("not an address"))
        XCTAssertFalse(subnet.contains("999.1.1.1"))
    }

    func testLogRetentionKeepsNewest300EntriesInOrder() {
        var log = DiagnosticLog()
        for index in 0..<350 {
            log.append(level: .info, category: "test", message: "entry \(index)")
        }
        XCTAssertEqual(log.entries.count, 300)
        XCTAssertEqual(log.entries.first?.message, "entry 50")
        XCTAssertEqual(log.entries.last?.message, "entry 349")
        XCTAssertEqual(Set(log.entries.map(\.id)).count, 300)
    }

    func testLogTimestampsFallWithinAppendInterval() throws {
        var log = DiagnosticLog()
        let before = Date()
        log.append(level: .warning, category: "Bonjour", message: "No advertised services observed.")
        let after = Date()
        let entry = try XCTUnwrap(log.entries.first)
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
        XCTAssertEqual(entry.level, .warning)
    }

    func testLogBoundsUnicodeByCharacters() throws {
        var log = DiagnosticLog()
        log.append(level: .error, category: String(repeating: "診", count: 100),
                   message: String(repeating: "🧑‍🚀", count: 3_000))
        let entry = try XCTUnwrap(log.entries.first)
        XCTAssertEqual(entry.category.count, DiagnosticLog.maxCategoryCharacters)
        XCTAssertEqual(entry.message.count, DiagnosticLog.maxMessageCharacters)
        XCTAssertTrue(entry.message.hasSuffix("🧑‍🚀"))
    }

    func testURLsWithUserInfoPathQueryAndFragmentAreRedactedBeforeStorage() throws {
        var log = DiagnosticLog()
        log.append(level: .error, category: "request",
                   message: "Failed https://name:privatepass@example.invalid/privatepath?token=privatequery#privatefragment and rtsp://example.invalid/streamSecret")
        let message = try XCTUnwrap(log.entries.first?.message)
        for secret in ["name", "privatepass", "privatepath", "privatequery", "privatefragment", "streamSecret"] {
            XCTAssertFalse(message.contains(secret), secret)
        }
        XCTAssertTrue(message.contains("[URL redacted]"))
    }

    func testCommonCredentialLabelsAndBearerTokensAreRedacted() {
        for message in ["password=hidden-value", "PASSWORD: hidden-value with spaces",
                        #"{"access_token":"hidden-value","extra":1}"#,
                        "api-key = hidden-value", "client_secret='hidden-value'",
                        "Authorization: Basic hidden-value", "Cookie: session=hidden-value",
                        "Bearer hidden-value", "refreshToken=hidden-value"] {
            var log = DiagnosticLog()
            log.append(level: .error, category: "test", message: message)
            XCTAssertFalse(log.entries[0].message.contains("hidden-value"), message)
        }
    }

    func testRedactionHandlesEachLineAndCategory() throws {
        var log = DiagnosticLog()
        log.append(level: .info, category: "password=categorySecret",
                   message: "password=firstSecret\nstatus unchanged\nToken: secondSecret\0")
        let entry = try XCTUnwrap(log.entries.first)
        XCTAssertFalse(entry.category.contains("categorySecret"))
        XCTAssertFalse(entry.message.contains("firstSecret"))
        XCTAssertFalse(entry.message.contains("secondSecret"))
        XCTAssertFalse(entry.message.contains("\0"))
        XCTAssertTrue(entry.message.contains("status unchanged"))
    }

    func testExportIsValidJSONAndPreservesStructuredFields() throws {
        var log = DiagnosticLog()
        log.append(level: .error, category: "Wi-Fi", message: "介面尚未取得 IPv4。")
        let json = try log.exportJSON()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticLog.self, from: data)
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].id, log.entries[0].id)
        XCTAssertEqual(decoded.entries[0].level, .error)
        XCTAssertEqual(decoded.entries[0].category, "Wi-Fi")
        XCTAssertEqual(decoded.entries[0].message, "介面尚未取得 IPv4。")
        XCTAssertLessThan(abs(decoded.entries[0].timestamp.timeIntervalSince(log.entries[0].timestamp)), 1)
    }

    func testExportContainsNoPreviouslySuppliedLabelledSecrets() throws {
        var log = DiagnosticLog()
        log.append(level: .error, category: "test", message: "token=do-not-export-this")
        XCTAssertFalse(try log.exportJSON().contains("do-not-export-this"))
    }

    func testDecodingUntrustedLogAppliesRetentionRedactionAndSizeBounds() throws {
        let entries: [[String: Any]] = (0..<305).map { index in
            ["id": UUID().uuidString, "timestamp": 0, "level": "info",
             "category": String(repeating: "X", count: 100),
             "message": "entry \(index)\npassword=decodedSecret"]
        }
        let data = try JSONSerialization.data(withJSONObject: ["entries": entries])
        let decoded = try JSONDecoder().decode(DiagnosticLog.self, from: data)
        XCTAssertEqual(decoded.entries.count, 300)
        XCTAssertTrue(decoded.entries[0].message.hasPrefix("entry 5\n"))
        XCTAssertEqual(decoded.entries[0].category.count, 64)
        XCTAssertFalse(try decoded.exportJSON().contains("decodedSecret"))
    }

    func testClearRemovesAllEntries() throws {
        var log = DiagnosticLog()
        log.append(level: .info, category: "test", message: "temporary")
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        let data = Data(try log.exportJSON().utf8)
        let decoded = try JSONDecoder().decode(DiagnosticLog.self, from: data)
        XCTAssertTrue(decoded.entries.isEmpty)
    }
}
