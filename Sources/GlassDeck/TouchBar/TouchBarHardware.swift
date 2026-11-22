import Foundation
import IOKit

/// Detects the Touch Bar panel in the IO registry.
///
/// The Touch Bar's own display publishes a `dfr` property; matching on it is
/// stable across Intel and Apple silicon MacBook Pros and reports `false` on
/// every Mac that never shipped one.
enum TouchBarHardware {
    static let isPresent: Bool = {
        guard let matching = IOServiceMatching("IOService") as NSMutableDictionary? else { return false }
        matching[kIOPropertyMatchKey] = ["dfr": true] as NSDictionary

        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching as CFDictionary,
            &iterator
        ) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return false }
        IOObjectRelease(entry)
        return true
    }()
}
