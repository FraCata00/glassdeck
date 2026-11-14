import GlassDeckKit
import SwiftUI

/// One row per time zone: what time it is there, and how far that is from here.
///
/// Fed a `Date` from outside rather than reading the clock itself, so the whole
/// card — and the menu bar with it — turns over on one wake-up a minute. See
/// `ClockTicker`.
struct ClockCard: View {
    let zones: [ClockZone]
    let now: Date

    var body: some View {
        ModuleCard(module: .clock, headline: WorldClock.time(in: .current, at: now)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(readings) { reading in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(reading.zone.displayLabel)
                            .font(Typography.label)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(reading.caption)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(reading.time)
                            .font(Typography.value)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }

    private var readings: [ClockReading] {
        zones.map { WorldClock.reading(for: $0, at: now) }
    }
}
