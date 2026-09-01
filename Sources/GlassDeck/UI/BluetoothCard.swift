import GlassDeckKit
import SwiftUI

/// The paired devices that carry a battery, live ones first.
///
/// A disconnected device is kept rather than hidden, dimmed and labelled: the
/// stack goes on publishing the charge it last saw, with nothing to mark it
/// stale, so the honest thing is to show the number *and* say it is old. Hiding
/// them instead would empty the card every time the earbuds went back in their
/// case.
struct BluetoothCard: View {
    let status: BluetoothStatus

    var body: some View {
        ModuleCard(module: .bluetooth, headline: status.headline) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(status.devices) { device in
                    row(for: device)
                }
            }
        }
    }

    private func row(for device: BluetoothDevice) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(device.isConnected ? Theme.accent(ModuleKind.bluetooth) : .secondary)
                    .frame(width: 16)
                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if !device.isConnected {
                    Text("not connected")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 12) {
                ForEach(Array(device.battery.levels.enumerated()), id: \.offset) { _, level in
                    BatteryPip(label: level.label, fraction: level.value, isDimmed: !device.isConnected)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
        }
        .opacity(device.isConnected ? 1 : 0.7)
    }
}
