import Foundation
import Darwin

struct NetworkTotals {
    struct Counter { let received: UInt64; let sent: UInt64 }
    let interfaces: [String: Counter]

    func delta(since previous: Self) -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0, sent: UInt64 = 0
        for (name, value) in interfaces {
            guard let old = previous.interfaces[name] else { continue }
            if value.received >= old.received { received &+= value.received - old.received }
            if value.sent >= old.sent { sent &+= value.sent - old.sent }
        }
        return (received, sent)
    }
}

enum NetworkReader {
    static func totals() -> NetworkTotals? {
        // NET_RT_IFLIST2 supplies if_data64; widening getifaddrs' 32-bit
        // counters after reading them cannot prevent their 4 GiB wraparound.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<2 {
            var count = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &count, nil, 0) == 0 else { return nil }
            var data = Data(count: count)
            let result = data.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &count, nil, 0) }
            if result != 0 { continue }
            data.count = count
            return parse(data)
        }
        return nil
    }

    static func parse(_ data: Data) -> NetworkTotals? {
        var offset = 0, counters: [String: NetworkTotals.Counter] = [:]
        while offset + 4 <= data.count {
            let length = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) })
            guard length >= 4, offset + length <= data.count else { return nil }
            if data[offset + 3] == RTM_IFINFO2 {
                guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
                let message = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self) }
                var bytes = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(message.ifm_index), &bytes) != nil {
                    let name = String(cString: bytes)
                    if name != "lo0" && !name.hasPrefix("utun") && !name.hasPrefix("awdl") {
                        counters[name] = .init(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                    }
                }
            }
            offset += length
        }
        return offset == data.count ? NetworkTotals(interfaces: counters) : nil
    }
}
