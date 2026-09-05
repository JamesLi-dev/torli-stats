import Foundation
import Darwin

struct NetworkTotals {
    let received: UInt64
    let sent: UInt64
}

enum NetworkReader {
    static func totals() -> NetworkTotals {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            return NetworkTotals(received: 0, sent: 0)
        }
        defer { freeifaddrs(addressList) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = current {
            let item = interface.pointee
            let name = String(cString: item.ifa_name)
            let isIgnored = name == "lo0" || name.hasPrefix("utun") || name.hasPrefix("awdl")
            if !isIgnored, item.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = item.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(stats.ifi_ibytes)
                sent += UInt64(stats.ifi_obytes)
            }
            current = item.ifa_next
        }

        return NetworkTotals(received: received, sent: sent)
    }
}
