import Foundation
import IOKit

enum IORegistryReader {
    static func properties(matching className: String, recursive: Bool = false) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        var visited = Set<UInt64>()
        func append(_ entry: io_registry_entry_t) {
            var identifier: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS,
               !visited.insert(identifier).inserted { return }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let value = properties?.takeRetainedValue() as? [String: Any] { result.append(value) }
        }
        while case let service = IOIteratorNext(iterator), service != 0 {
            append(service)
            if recursive {
                var children: io_iterator_t = 0
                if IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS {
                    while case let child = IOIteratorNext(children), child != 0 {
                        append(child)
                        IOObjectRelease(child)
                    }
                    IOObjectRelease(children)
                }
            }
            IOObjectRelease(service)
        }
        return result
    }
}
