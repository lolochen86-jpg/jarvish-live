import Foundation

/// IPv4 arithmetic only. An interface address and netmask do not identify a
/// gateway, a helmet, a reachable host, or an application protocol.
struct IPv4Subnet: Equatable {
    enum ValidationError: Error, LocalizedError, Equatable {
        case invalidAddress
        case invalidMask
        case nonContiguousMask

        var errorDescription: String? {
            switch self {
            case .invalidAddress: return "IPv4 位址格式無效。"
            case .invalidMask: return "IPv4 子網路遮罩格式無效。"
            case .nonContiguousMask: return "子網路遮罩的 1 位元必須連續。"
            }
        }
    }

    let address: String
    let mask: String
    let prefixLength: Int
    let networkAddress: String
    /// The upper address in the subnet. /31 and /32 do not imply a usable
    /// directed-broadcast destination. This property never triggers traffic.
    let broadcastAddress: String
    private let maskValue: UInt32
    private let networkValue: UInt32

    init(address: String, mask: String) throws {
        guard let addressValue = Self.parse(address) else {
            throw ValidationError.invalidAddress
        }
        guard let parsedMask = Self.parse(mask) else {
            throw ValidationError.invalidMask
        }
        let inverse = ~parsedMask
        // The inverse of a contiguous mask is 0 or (2^n - 1). Wrapping
        // addition deliberately includes /0 without an overflow trap.
        guard inverse & (inverse &+ 1) == 0 else {
            throw ValidationError.nonContiguousMask
        }
        let network = addressValue & parsedMask
        self.address = Self.format(addressValue)
        self.mask = Self.format(parsedMask)
        self.prefixLength = parsedMask.nonzeroBitCount
        self.networkAddress = Self.format(network)
        self.broadcastAddress = Self.format(network | inverse)
        self.maskValue = parsedMask
        self.networkValue = network
    }

    /// Membership is address arithmetic, not reachability or device identity.
    func contains(_ address: String) -> Bool {
        guard let value = Self.parse(address) else { return false }
        return value & maskValue == networkValue
    }

    private static func parse(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            // Reject ambiguous octal-style notation, signs, whitespace,
            // non-ASCII digits, empty octets, and abbreviated addresses.
            guard !part.isEmpty, part.count <= 3,
                  part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  part.count == 1 || part.first != "0",
                  let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }

    private static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case info
    case warning
    case error
}

struct LogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel,
         category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = LogRedactor.sanitize(category, limit: DiagnosticLog.maxCategoryCharacters)
        self.message = LogRedactor.sanitize(message, limit: DiagnosticLog.maxMessageCharacters)
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, level, category, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            level: try container.decode(LogLevel.self, forKey: .level),
            category: try container.decode(String.self, forKey: .category),
            message: try container.decode(String.self, forKey: .message)
        )
    }
}

/// Local, in-memory diagnostic history. Sharing is an explicit UI action;
/// this type neither persists to disk nor sends data to a server.
struct DiagnosticLog: Codable {
    static let maxEntries = 300
    static let maxCategoryCharacters = 64
    static let maxMessageCharacters = 2_000

    private(set) var entries: [LogEntry]

    init() {
        entries = []
    }

    mutating func append(level: LogLevel, category: String, message: String) {
        entries.append(LogEntry(level: level, category: category, message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    mutating func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    func exportJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    private enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // LogEntry decoding also applies redaction and size bounds.
        entries = Array(try container.decode([LogEntry].self, forKey: .entries)
            .suffix(Self.maxEntries))
    }
}

private enum LogRedactor {
    /// Defensive redaction, not a secret detector. Callers must never provide
    /// credentials or raw Bonjour TXT payloads. Unlabelled secrets cannot be
    /// recognized reliably. URLs are removed in full because credentials can
    /// also occur in their path, rather than only user-info or query strings.
    static func sanitize(_ input: String, limit: Int) -> String {
        var result = input.replacingOccurrences(of: "\0", with: "")
        let rules: [(String, String)] = [
            (#"(?i)\b[a-z][a-z0-9+.-]*://[^\s<>\"']+"#, "[URL redacted]"),
            (#"(?i)\b(authorization|proxy-authorization|cookie|set-cookie)\b[\"']?\s*[:=]\s*[^\r\n]*"#, "$1=[REDACTED]"),
            (#"(?i)\b(password|passwd|pwd|token|access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?key|client[_-]?secret|secret|credential)\b[\"']?\s*[:=]\s*[^\r\n]*"#, "$1=[REDACTED]"),
            (#"(?i)\bBearer\s+[^\s,;]+"#, "Bearer [REDACTED]")
        ]
        for (pattern, replacement) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                     withTemplate: replacement)
        }
        return String(result.prefix(limit))
    }
}
