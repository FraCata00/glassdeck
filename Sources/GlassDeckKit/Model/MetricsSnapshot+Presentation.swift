import Foundation

// The words and numbers the surfaces show for a reading, kept apart from the
// readings themselves. Everything here is localised through the kit's own
// string table; see `L`.

extension MetricsSnapshot {
    /// The numbers behind a metric's headline, shown when a card or a Touch Bar
    /// panel is expanded.
    public func details(for kind: MetricKind) -> [MetricDetail] {
        switch kind {
        case .cpu:
            var items = [
                MetricDetail(label: L.t("detail.user", "user"), value: ValueFormatter.percent(cpu.user)),
                MetricDetail(label: L.t("detail.system", "system"), value: ValueFormatter.percent(cpu.system)),
            ]
            if let performance = cpu.performanceClusterLoad {
                items.append(MetricDetail(label: "P-cores", value: ValueFormatter.percent(performance)))
            }
            if let efficiency = cpu.efficiencyClusterLoad {
                items.append(MetricDetail(label: "E-cores", value: ValueFormatter.percent(efficiency)))
            }
            if let load = cpu.loadAverage.first {
                items.append(MetricDetail(label: L.t("detail.load", "load 1m"), value: ValueFormatter.decimal(load)))
            }
            return items

        case .gpu:
            guard gpu.isAvailable else { return [MetricDetail(label: L.t("detail.gpu", "gpu"), value: L.t("value.na", "n/a"))] }
            return [
                MetricDetail(label: L.t("detail.device", "device"), value: ValueFormatter.percent(gpu.utilisation)),
                MetricDetail(label: L.t("detail.renderer", "renderer"), value: ValueFormatter.percent(gpu.rendererUtilisation)),
                MetricDetail(label: L.t("detail.tiler", "tiler"), value: ValueFormatter.percent(gpu.tilerUtilisation)),
                MetricDetail(label: "vram", value: ValueFormatter.bytes(gpu.allocatedMemory)),
            ]

        case .memory:
            return [
                MetricDetail(label: L.t("detail.used", "used"), value: ValueFormatter.bytes(memory.used)),
                MetricDetail(label: L.t("detail.wired", "wired"), value: ValueFormatter.bytes(memory.wired)),
                MetricDetail(label: L.t("detail.compressed", "compressed"), value: ValueFormatter.bytes(memory.compressed)),
                MetricDetail(label: L.t("detail.swap", "swap"), value: ValueFormatter.bytes(memory.swapUsed)),
            ]

        case .disk:
            return [
                MetricDetail(label: L.t("detail.used", "used"), value: ValueFormatter.bytes(disk.used)),
                MetricDetail(label: L.t("detail.free", "free"), value: ValueFormatter.bytes(disk.free)),
                MetricDetail(label: L.t("detail.read", "read"), value: ValueFormatter.rate(disk.readBytesPerSecond)),
                MetricDetail(label: L.t("detail.write", "write"), value: ValueFormatter.rate(disk.writeBytesPerSecond)),
            ]

        case .network:
            return [
                MetricDetail(label: L.t("detail.down", "down"), value: ValueFormatter.rate(network.downloadBytesPerSecond)),
                MetricDetail(label: L.t("detail.up", "up"), value: ValueFormatter.rate(network.uploadBytesPerSecond)),
            ]

        case .fans:
            guard fans.isAvailable else { return [MetricDetail(label: L.t("detail.fans", "fans"), value: L.t("value.none", "none"))] }
            let speeds = fans.fans.map { fan in
                MetricDetail(
                    label: fans.fans.count > 1
                        ? L.t("detail.fanIndex", "fan %lld", fan.index + 1)
                        : L.t("detail.speed", "speed"),
                    value: fan.rpm > 0 ? L.t("value.rpm", "%lld rpm", Int(fan.rpm.rounded())) : L.t("value.idle", "idle")
                )
            }
            let maximum = fans.fans.map(\.maximumRPM).max() ?? 0
            return speeds + [
                MetricDetail(
                    label: L.t("detail.max", "max"),
                    value: L.t("value.rpm", "%lld rpm", Int(maximum))
                ),
            ]

        case .battery:
            guard battery.isAvailable else { return [MetricDetail(label: L.t("detail.battery", "battery"), value: L.t("value.none", "none"))] }
            var items = [
                MetricDetail(label: L.t("detail.charge", "charge"), value: battery.headline),
                MetricDetail(
                    label: L.t("detail.state", "state"),
                    value: battery.stateLabel
                ),
            ]
            if let minutes = battery.minutesRemaining {
                items.append(
                    MetricDetail(
                        label: battery.isCharging ? L.t("detail.toFull", "to full") : L.t("detail.remaining", "remaining"),
                        value: ValueFormatter.duration(minutes: minutes)
                    )
                )
            }
            // Draw belongs here rather than in the battery chip: it is the number
            // you want once you are already asking about power.
            if power.isAvailable {
                items.append(MetricDetail(label: L.t("detail.draw", "draw"), value: power.headline))
            }
            return items

        case .temperature:
            guard thermal.isAvailable else { return [MetricDetail(label: L.t("detail.sensors", "sensors"), value: L.t("value.none", "none"))] }
            var items: [MetricDetail] = []
            if let cpu = thermal.cpu { items.append(MetricDetail(label: L.t("detail.cpu", "cpu"), value: ValueFormatter.celsius(cpu))) }
            if let gpu = thermal.gpu { items.append(MetricDetail(label: L.t("detail.gpu", "gpu"), value: ValueFormatter.celsius(gpu))) }
            if let battery = thermal.battery {
                items.append(MetricDetail(label: L.t("detail.battery", "battery"), value: ValueFormatter.celsius(battery)))
            }
            if let enclosure = thermal.enclosure {
                items.append(MetricDetail(label: L.t("detail.case", "case"), value: ValueFormatter.celsius(enclosure)))
            }
            return items

        case .power:
            guard power.isAvailable else { return [MetricDetail(label: L.t("detail.power", "power"), value: L.t("value.na", "n/a"))] }
            var items = [MetricDetail(label: L.t("detail.now", "now"), value: power.headline)]
            if let adapter = power.adapterWatts, adapter > 5 {
                items.append(MetricDetail(label: L.t("detail.adapter", "adapter"), value: "\(Int(adapter.rounded())) W"))
            }
            if battery.isAvailable {
                items.append(MetricDetail(label: L.t("detail.source", "source"), value: battery.isPluggedIn ? L.t("value.wall", "wall") : L.t("value.battery", "battery")))
            }
            return items
        }
    }

    /// The short, human readable value shown under a gauge (e.g. `42%`, `9.1 GB`).
    public func headline(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: ValueFormatter.percent(cpu.total)
        case .gpu: gpu.isAvailable ? ValueFormatter.percent(gpu.utilisation) : L.t("value.na", "n/a")
        case .memory: ValueFormatter.bytes(memory.used)
        case .disk: ValueFormatter.rate(disk.busiestBytesPerSecond)
        case .network: ValueFormatter.rate(network.downloadBytesPerSecond)
        case .fans: fans.headline
        case .battery: battery.headline
        case .temperature: thermal.headline
        case .power: power.headline
        }
    }

    /// The secondary caption shown under the headline.
    public func caption(for kind: MetricKind) -> String {
        switch kind {
        case .cpu:
            L.t("cpu.caption", "%1$@ user · %2$@ sys", ValueFormatter.percent(cpu.user), ValueFormatter.percent(cpu.system))
        case .gpu:
            gpu.isAvailable ? gpu.name : L.t("gpu.none", "no accelerator")
        case .memory:
            L.t("memory.caption", "%1$@ total · %2$@ swap", ValueFormatter.bytes(memory.total), ValueFormatter.bytes(memory.swapUsed))
        case .disk:
            L.t("disk.caption", "%1$@ free of %2$@", ValueFormatter.bytes(disk.free), ValueFormatter.bytes(disk.total))
        case .network:
            "↓ \(ValueFormatter.rate(network.downloadBytesPerSecond)) ↑ \(ValueFormatter.rate(network.uploadBytesPerSecond))"
        case .fans:
            fans.caption
        case .battery:
            battery.caption
        case .temperature:
            thermal.caption
        case .power:
            power.caption
        }
    }
}

extension FanUsage {
    public var headline: String {
        guard isAvailable else { return L.t("value.na", "n/a") }
        guard topRPM > 0 else { return L.t("value.idle", "idle") }
        return L.t("value.rpm", "%lld rpm", Int(topRPM.rounded()))
    }

    public var caption: String {
        guard isAvailable else { return L.t("fans.none", "fanless Mac") }
        if fans.count > 1 {
            return fans.map { "\(Int($0.rpm.rounded()))" }.joined(separator: " · ") + " rpm"
        }
        guard let fan = fans.first else { return L.t("fans.missing", "no fan") }
        return L.t("fans.range", "range %1$lld–%2$lld rpm", Int(fan.minimumRPM), Int(fan.maximumRPM))
    }
}

extension BatteryUsage {
    public var headline: String { isAvailable ? "\(percentage)%" : L.t("value.na", "n/a") }

    public var caption: String {
        guard isAvailable else { return L.t("battery.none", "no battery") }
        let state = stateLabel
        guard let minutesRemaining else { return state }
        let remaining = ValueFormatter.duration(minutes: minutesRemaining)
        return isCharging
            ? L.t("battery.toFull", "%1$@ · %2$@ to full", state, remaining)
            : L.t("battery.left", "%1$@ · %2$@ left", state, remaining)
    }

    /// What the battery is doing: charging, held on the adapter without
    /// charging, or running the machine.
    public var stateLabel: String {
        if isCharging { return L.t("battery.charging", "charging") }
        return isPluggedIn ? L.t("battery.onPower", "on power") : L.t("battery.onBattery", "on battery")
    }

    /// SF Symbol matching the current level, mirroring the system's own glyph set.
    public var symbolName: String {
        guard isAvailable else { return "battery.slash" }
        if isCharging { return "battery.100.bolt" }
        switch fraction {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}

extension ThermalUsage {
    public var headline: String {
        guard let hottest else { return L.t("value.na", "n/a") }
        return ValueFormatter.celsius(hottest)
    }

    public var caption: String {
        guard isAvailable else { return L.t("thermal.none", "no sensors") }
        var parts: [String] = []
        if let cpu { parts.append("CPU \(Int(cpu.rounded()))°") }
        if let gpu { parts.append("GPU \(Int(gpu.rounded()))°") }
        if let battery { parts.append(L.t("thermal.battery", "battery %lld°", Int(battery.rounded()))) }
        if let enclosure, parts.count < 3 { parts.append(L.t("thermal.case", "case %lld°", Int(enclosure.rounded()))) }
        return parts.isEmpty ? L.t("thermal.none", "no sensors") : parts.joined(separator: " · ")
    }
}

extension PowerUsage {
    public var headline: String {
        guard isAvailable else { return L.t("value.na", "n/a") }
        return watts < 10 ? String(format: "%.1f W", watts) : "\(Int(watts.rounded())) W"
    }

    public var caption: String {
        guard isAvailable else { return L.t("power.none", "not reported") }
        guard let adapterWatts, adapterWatts > 5 else { return L.t("power.total", "system total") }
        return L.t("power.adapter", "of a %lld W adapter", Int(adapterWatts.rounded()))
    }
}
