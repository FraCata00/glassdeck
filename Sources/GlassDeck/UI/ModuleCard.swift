import GlassDeckKit
import SwiftUI

/// The shared chrome of a module card: the icon chip and title every metric
/// card has, a headline on the right, and whatever the module puts below.
///
/// The metric cards cannot be reused for this. What they draw — a ring, a
/// sparkline, a fill bar — is the shape of a single fraction, and a module has
/// none; what they share with these is only the header.
struct ModuleCard<Content: View>: View {
    let module: ModuleKind
    var headline: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.iconChip(module))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: module.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent(module))
                    }
                Text(module.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let headline {
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Theme.tileCornerRadius)
    }
}

/// A charge as a short bar plus its percentage, used once per battery a device
/// reports — which for a pair of earbuds is three.
struct BatteryPip: View {
    let label: String
    let fraction: Double
    var isDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(ValueFormatter.percent(fraction))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(.primary.opacity(0.09))
                .frame(width: 44, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, 44 * fraction.clamped01), height: 3)
                }
        }
        .opacity(isDimmed ? 0.55 : 1)
    }

    /// Charge runs the other way from load: a full battery is the good end, so
    /// the shared status tint is read upside down.
    private var tint: Color {
        Theme.statusTint(1 - fraction.clamped01)
    }
}

extension ModuleKind {
    /// Whether the module has anything worth a card right now.
    ///
    /// The same courtesy the metrics get: a fanless Mac is not shown an empty
    /// fan gauge, and a Mac with nothing paired is not shown an empty Bluetooth
    /// card.
    @MainActor
    func hasContent(in snapshot: MetricsSnapshot, preferences: Preferences) -> Bool {
        switch self {
        case .bluetooth: snapshot.bluetooth.isAvailable
        case .clock: !preferences.clockZones.isEmpty
        }
    }
}

/// The card for a module, whichever it is.
struct ModuleCardView: View {
    let module: ModuleKind
    let snapshot: MetricsSnapshot
    let zones: [ClockZone]
    let now: Date

    var body: some View {
        switch module {
        case .bluetooth: BluetoothCard(status: snapshot.bluetooth)
        case .clock: ClockCard(zones: zones, now: now)
        }
    }
}
