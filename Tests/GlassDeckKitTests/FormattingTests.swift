import Testing
@testable import GlassDeckKit

@Suite("Value formatting")
struct FormattingTests {
    @Test("Percentages round to the nearest whole number")
    func percentRounds() {
        #expect(ValueFormatter.percent(0) == "0%")
        #expect(ValueFormatter.percent(0.4213) == "42%")
        #expect(ValueFormatter.percent(0.999) == "100%")
    }

    @Test("Percentages clamp out-of-range and non-finite input")
    func percentClamps() {
        #expect(ValueFormatter.percent(-3) == "0%")
        #expect(ValueFormatter.percent(4.5) == "100%")
        #expect(ValueFormatter.percent(.nan) == "0%")
    }

    @Test("Byte counts switch to binary units with adaptive precision")
    func bytesFormatting() {
        #expect(ValueFormatter.bytes(512) == "512 B")
        #expect(ValueFormatter.bytes(1024) == "1.0 KB")
        #expect(ValueFormatter.bytes(9 * 1024 * 1024 * 1024) == "9.0 GB")
        // Ten and above drops the decimal so the label stays narrow.
        #expect(ValueFormatter.bytes(16 * 1024 * 1024 * 1024) == "16 GB")
    }

    @Test("Rates carry a per-second suffix and never go negative")
    func rateFormatting() {
        #expect(ValueFormatter.rate(1_048_576) == "1.0 MB/s")
        #expect(ValueFormatter.rate(-5) == "0 B/s")
        #expect(ValueFormatter.rate(.infinity) == "0 B/s")
    }
}

@Suite("Math helpers")
struct MathTests {
    @Test("clamped01 keeps values inside the unit interval")
    func clamping() {
        #expect(0.5.clamped01 == 0.5)
        #expect((-2.0).clamped01 == 0)
        #expect(7.0.clamped01 == 1)
        #expect(Double.nan.clamped01 == 0)
        #expect(Double.infinity.clamped01 == 1)
    }

    @Test("mean of an empty collection is zero, not a crash")
    func meanOfEmpty() {
        #expect([Double]().mean == 0)
        #expect([1.0, 2.0, 3.0].mean == 2)
    }
}
