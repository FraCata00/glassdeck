import GlassDeckKit
import SwiftUI

/// The expanded view of whichever metric is selected: history curve plus the
/// two or three numbers that actually matter for that metric.
struct MetricDetailCard: View {
    let kind: MetricKind
    let snapshot: MetricsSnapshot
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(kind.title, systemImage: kind.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.headline(for: kind))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Sparkline(values: history, gradient: Theme.gradient(kind))
                .frame(height: 44)

            HStack(spacing: 14) {
                ForEach(details, id: \.label) { detail in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(detail.value)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                        Text(detail.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if detail.label != details.last?.label { Spacer(minLength: 0) }
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: Theme.tileCornerRadius)
    }

    private struct Detail {
        let label: String
        let value: String
    }

    private var details: [Detail] {
        switch kind {
        case .cpu:
            var items = [
                Detail(label: "user", value: ValueFormatter.percent(snapshot.cpu.user)),
                Detail(label: "system", value: ValueFormatter.percent(snapshot.cpu.system)),
            ]
            if let performance = snapshot.cpu.performanceClusterLoad {
                items.append(Detail(label: "P-cores", value: ValueFormatter.percent(performance)))
            }
            if let efficiency = snapshot.cpu.efficiencyClusterLoad {
                items.append(Detail(label: "E-cores", value: ValueFormatter.percent(efficiency)))
            }
            if let load = snapshot.cpu.loadAverage.first {
                items.append(Detail(label: "load 1m", value: ValueFormatter.decimal(load)))
            }
            return items
        case .gpu:
            return [
                Detail(label: "device", value: ValueFormatter.percent(snapshot.gpu.utilisation)),
                Detail(label: "renderer", value: ValueFormatter.percent(snapshot.gpu.rendererUtilisation)),
                Detail(label: "tiler", value: ValueFormatter.percent(snapshot.gpu.tilerUtilisation)),
                Detail(label: "vram", value: ValueFormatter.bytes(snapshot.gpu.allocatedMemory)),
            ]
        case .memory:
            return [
                Detail(label: "used", value: ValueFormatter.bytes(snapshot.memory.used)),
                Detail(label: "wired", value: ValueFormatter.bytes(snapshot.memory.wired)),
                Detail(label: "compressed", value: ValueFormatter.bytes(snapshot.memory.compressed)),
                Detail(label: "swap", value: ValueFormatter.bytes(snapshot.memory.swapUsed)),
            ]
        case .disk:
            return [
                Detail(label: "used", value: ValueFormatter.bytes(snapshot.disk.used)),
                Detail(label: "free", value: ValueFormatter.bytes(snapshot.disk.free)),
                Detail(label: "read", value: ValueFormatter.rate(snapshot.disk.readBytesPerSecond)),
                Detail(label: "write", value: ValueFormatter.rate(snapshot.disk.writeBytesPerSecond)),
            ]
        case .network:
            return [
                Detail(label: "down", value: ValueFormatter.rate(snapshot.network.downloadBytesPerSecond)),
                Detail(label: "up", value: ValueFormatter.rate(snapshot.network.uploadBytesPerSecond)),
            ]
        case .fans:
            guard snapshot.fans.isAvailable else {
                return [Detail(label: "fans", value: "none")]
            }
            return snapshot.fans.fans.map { fan in
                Detail(
                    label: snapshot.fans.fans.count > 1 ? "fan \(fan.index + 1)" : "speed",
                    value: fan.rpm > 0 ? "\(Int(fan.rpm.rounded())) rpm" : "idle"
                )
            } + [
                Detail(label: "max", value: "\(Int(snapshot.fans.fans.map(\.maximumRPM).max() ?? 0)) rpm")
            ]
        case .battery:
            guard snapshot.battery.isAvailable else {
                return [Detail(label: "battery", value: "none")]
            }
            var items = [
                Detail(label: "charge", value: snapshot.battery.headline),
                Detail(
                    label: "state",
                    value: snapshot.battery.isCharging
                        ? "charging"
                        : (snapshot.battery.isPluggedIn ? "on power" : "on battery")
                ),
            ]
            if let minutes = snapshot.battery.minutesRemaining {
                items.append(
                    Detail(
                        label: snapshot.battery.isCharging ? "to full" : "remaining",
                        value: minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
                    )
                )
            }
            return items
        case .temperature:
            guard snapshot.thermal.isAvailable else {
                return [Detail(label: "sensors", value: "none")]
            }
            var items: [Detail] = []
            if let cpu = snapshot.thermal.cpu {
                items.append(Detail(label: "cpu", value: "\(Int(cpu.rounded()))°C"))
            }
            if let gpu = snapshot.thermal.gpu {
                items.append(Detail(label: "gpu", value: "\(Int(gpu.rounded()))°C"))
            }
            if let battery = snapshot.thermal.battery {
                items.append(Detail(label: "battery", value: "\(Int(battery.rounded()))°C"))
            }
            if let enclosure = snapshot.thermal.enclosure {
                items.append(Detail(label: "case", value: "\(Int(enclosure.rounded()))°C"))
            }
            return items
        case .power:
            guard snapshot.power.isAvailable else {
                return [Detail(label: "power", value: "n/a")]
            }
            var items = [Detail(label: "now", value: snapshot.power.headline)]
            if let adapter = snapshot.power.adapterWatts, adapter > 5 {
                items.append(Detail(label: "adapter", value: "\(Int(adapter.rounded())) W"))
            }
            if snapshot.battery.isAvailable {
                items.append(
                    Detail(
                        label: "source",
                        value: snapshot.battery.isPluggedIn ? "wall" : "battery"
                    )
                )
            }
            return items
        }
    }
}
