import Foundation
import Testing
@testable import GlassDeckKit

@Suite("SMC decoding")
struct SMCDecodingTests {
    private func littleEndian(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    @Test("Each numeric type decodes in its own byte order")
    func numericTypes() {
        #expect(SMCService.decode(type: "flt ", bytes: littleEndian(42.5)) == 42.5)
        #expect(SMCService.decode(type: "fpe2", bytes: [0x17, 0x70]) == 1500)
        #expect(SMCService.decode(type: "sp78", bytes: [0x2a, 0x80]) == 42.5)
        #expect(SMCService.decode(type: "sp78", bytes: [0xff, 0x00]) == -1)
        #expect(SMCService.decode(type: "ui8 ", bytes: [3]) == 3)
        #expect(SMCService.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCService.decode(type: "ui32", bytes: [0, 0, 0x07, 0x08]) == 1800)
        #expect(SMCService.decode(type: "ui16", bytes: [0x01]) == nil)
        #expect(SMCService.decode(type: "ch8*", bytes: [0x41]) == nil)
    }

    @Test("A float that is not a number is not a reading")
    func nonFiniteFloatsAreRejected() {
        // These used to pass every `> 0` test: an infinite wattage was
        // reported as available, and an infinite fan count trapped in `Int(_:)`.
        #expect(SMCService.decode(type: "flt ", bytes: littleEndian(.infinity)) == nil)
        #expect(SMCService.decode(type: "flt ", bytes: littleEndian(-.infinity)) == nil)
        #expect(SMCService.decode(type: "flt ", bytes: littleEndian(.nan)) == nil)
    }
}
