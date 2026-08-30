import Foundation

/// A fixed-capacity FIFO of samples backing the sparklines.
///
/// Appending past `capacity` drops the oldest element, so history rendering never
/// has to trim or reallocate.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    public private(set) var storage: [Element]
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer needs a positive capacity")
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    public var values: [Element] { storage }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var last: Element? { storage.last }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
    }
}
