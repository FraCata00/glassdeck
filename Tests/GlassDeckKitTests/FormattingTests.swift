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
        // Just under ten rounds up to ten, and then drops its decimal too.
        #expect(ValueFormatter.bytes(10_695_475_200) == "10 GB")
    }

    @Test("Storage is counted in decimal units, the way Finder counts it")
    func storageFormatting() {
        // The boot volume of the machine this was measured on: Finder says
        // 494 GB with 228 GB available; binary units made it 460 and 213.
        #expect(ValueFormatter.storage(494_353_338_368) == "494 GB")
        #expect(ValueFormatter.storage(228_220_635_775) == "228 GB")
        #expect(ValueFormatter.storage(1_500_000_000_000) == "1.5 TB")
        #expect(ValueFormatter.storage(999) == "999 B")
    }

    @Test("Rates are decimal, carry a per-second suffix and never go negative")
    func rateFormatting() {
        // Activity Monitor's Disk and Network tabs count in powers of 1000.
        #expect(ValueFormatter.rate(1_000_000) == "1.0 MB/s")
        #expect(ValueFormatter.rate(40_988_672) == "41 MB/s")
        #expect(ValueFormatter.rate(-5) == "0 B/s")
        #expect(ValueFormatter.rate(.infinity) == "0 B/s")
    }

    @Test("A figure that rounds up to the next unit is printed in that unit")
    func roundingCrossesUnits() {
        // 1023.7 MB: under 1024 as measured, 1024 as printed.
        #expect(ValueFormatter.bytes(1_073_427_000) == "1.0 GB")
        // 999.96 KB in decimal units.
        #expect(ValueFormatter.storage(999_960) == "1.0 MB")
        #expect(ValueFormatter.rate(999_600) == "1.0 MB/s")
        // Just short of rounding up stays where it is.
        #expect(ValueFormatter.storage(999_400) == "999 KB")
        #expect(ValueFormatter.bytes(1023) == "1023 B")
    }

    @Test("Whole figures round a half up, as the decimals do")
    func wholeFiguresRoundHalfUp() {
        #expect(ValueFormatter.storage(10_500_000_000) == "11 GB")
        #expect(ValueFormatter.storage(12_500_000_000) == "13 GB")
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

    @Test("roundedInt never traps, whatever the reading")
    func roundedIntSaturates() {
        #expect(2.5.roundedInt == 3)
        #expect((-2.5).roundedInt == -3)
        #expect(Double.nan.roundedInt == 0)
        #expect(Double.infinity.roundedInt == .max)
        #expect((-Double.infinity).roundedInt == .min)
        #expect(1e300.roundedInt == .max)
    }

    @Test("mean of an empty collection is zero, not a crash")
    func meanOfEmpty() {
        #expect([Double]().mean == 0)
        #expect([1.0, 2.0, 3.0].mean == 2)
    }
}

@Suite("Durations and temperatures")
struct DurationAndTemperatureTests {
    @Test("Durations drop the hours below one")
    func durations() {
        #expect(ValueFormatter.duration(minutes: 0) == "0m")
        #expect(ValueFormatter.duration(minutes: 45) == "45m")
        #expect(ValueFormatter.duration(minutes: 60) == "1h 0m")
        #expect(ValueFormatter.duration(minutes: 125) == "2h 5m")
    }

    @Test("Temperatures round to the nearest degree")
    func temperatures() {
        #expect(ValueFormatter.celsius(54.4) == "54°C")
        #expect(ValueFormatter.celsius(54.5) == "55°C")
        #expect(ValueFormatter.celsius(-3.6) == "-4°C")
        #expect(ValueFormatter.celsius(.nan) == "0°C")
    }

    @Test("Readings the SMC decoded as NaN or infinity format instead of trapping")
    func nonFiniteReadingsFormat() {
        let fans = FanUsage(
            fans: [
                Fan(index: 0, rpm: .nan, minimumRPM: 1200, maximumRPM: 6000),
                Fan(index: 1, rpm: .infinity, minimumRPM: .nan, maximumRPM: .infinity),
            ],
            isAvailable: true
        )
        let snapshot = MetricsSnapshot(
            fans: fans,
            battery: BatteryUsage(fraction: .nan, isAvailable: true),
            power: PowerUsage(watts: .infinity, adapterWatts: .infinity, isAvailable: true)
        )
        for kind in MetricKind.allCases {
            _ = snapshot.headline(for: kind)
            _ = snapshot.caption(for: kind)
            _ = snapshot.details(for: kind)
        }
        #expect(snapshot.battery.percentage == 0)
        #expect(FanUsage(fans: [fans.fans[1]], isAvailable: true).caption.contains("rpm"))
    }

    @Test("Battery state reads charging before plugged in")
    func batteryState() {
        #expect(BatteryUsage(isCharging: true, isPluggedIn: true, isAvailable: true).stateLabel == "charging")
        #expect(BatteryUsage(isCharging: false, isPluggedIn: true, isAvailable: true).stateLabel == "on power")
        #expect(BatteryUsage(isCharging: false, isPluggedIn: false, isAvailable: true).stateLabel == "on battery")
    }
}
