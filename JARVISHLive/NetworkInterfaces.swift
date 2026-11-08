import Foundation
import Darwin

struct InterfaceAddress: Identifiable, Equatable, Codable {
    var id: String { "\(name)|\(family)|\(address)" }
    let name: String
    let address: String
    let netmask: String
    let family: String
}

enum NetworkInterfaceError: LocalizedError {
    case enumerationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .enumerationFailed(let code):
            return "getifaddrs 失敗（errno \(code)）：\(String(cString: strerror(code)))"
        }
    }
}

/// Reads addresses already assigned to this iPhone. It does not scan other hosts
/// and does not infer a gateway or device address from the local address.
enum NetworkInterfaces {
    static func current() throws -> [InterfaceAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else {
            throw NetworkInterfaceError.enumerationFailed(errno)
        }
        guard let first else { return [] }
        defer { freeifaddrs(first) }

        var result: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let entry = pointer.pointee
            cursor = entry.ifa_next
            guard (entry.ifa_flags & UInt32(IFF_UP)) != 0,
                  (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let socket = entry.ifa_addr else { continue }
            let family = Int32(socket.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6,
                  let address = numericAddress(socket, length: socklen_t(socket.pointee.sa_len)) else { continue }
            let netmask = entry.ifa_netmask.flatMap {
                numericAddress($0, length: socklen_t($0.pointee.sa_len))
            } ?? "未提供"
            result.append(InterfaceAddress(
                name: String(cString: entry.ifa_name),
                address: address,
                netmask: netmask,
                family: family == AF_INET ? "IPv4" : "IPv6"
            ))
        }
        return Array(Set(result.map(\.id))).compactMap { id in
            result.first { $0.id == id }
        }.sorted {
            ($0.name, $0.family, $0.address) < ($1.name, $1.family, $1.address)
        }
    }

    /// NetService addresses are packed sockaddr values, not strings. Copy into
    /// aligned storage before decoding; reject malformed/truncated data.
    static func numericAddress(from data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        var storage = sockaddr_storage()
        let copied = min(data.count, MemoryLayout<sockaddr_storage>.size)
        _ = withUnsafeMutableBytes(of: &storage) { destination in
            data.copyBytes(to: destination, from: 0..<copied)
        }
        let family = Int32(storage.ss_family)
        let minimumLength: Int
        switch family {
        case AF_INET: minimumLength = MemoryLayout<sockaddr_in>.size
        case AF_INET6: minimumLength = MemoryLayout<sockaddr_in6>.size
        default: return nil
        }
        let reportedLength = Int(storage.ss_len)
        guard reportedLength >= minimumLength,
              reportedLength <= copied else { return nil }
        return withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                numericAddress($0, length: socklen_t(reportedLength))
            }
        }
    }

    private static func numericAddress(_ socket: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        guard length > 0 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(socket, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
    }
}
