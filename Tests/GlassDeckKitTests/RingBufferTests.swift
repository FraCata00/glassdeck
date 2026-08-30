import Testing
@testable import GlassDeckKit

@Suite("Ring buffer")
struct RingBufferTests {
    @Test("Appending past capacity drops the oldest samples")
    func dropsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }

        #expect(buffer.values == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test("A fresh buffer is empty and stays within capacity")
    func startsEmpty() {
        var buffer = RingBuffer<Double>(capacity: 2)
        #expect(buffer.isEmpty)

        buffer.append(1)
        #expect(buffer.count == 1)

        buffer.removeAll()
        #expect(buffer.isEmpty)
        #expect(buffer.capacity == 2)
    }
}
