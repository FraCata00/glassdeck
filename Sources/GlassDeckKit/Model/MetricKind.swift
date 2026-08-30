import Foundation

/// The metrics GlassDeck can display, in their canonical order.
///
/// The raw value doubles as the persisted identifier in user defaults, so it must stay stable.
public enum MetricKind: String, Sendable, CaseIterable, Codable, Identifiable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case fans
    case battery
    case temperature
    case power

    public var id: String { rawValue }

    /// Title shown above a gauge.
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .fans: "Fans"
        case .battery: "Battery"
        case .temperature: "Temperature"
        case .power: "Power"
        }
    }

    /// Two or three character label used in the cramped Touch Bar strip.
    public var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .disk: "SSD"
        case .network: "NET"
        case .fans: "FAN"
        case .battery: "BAT"
        case .temperature: "TMP"
        case .power: "PWR"
        }
    }

    /// SF Symbol representing the metric.
    public var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .fans: "fanblades"
        case .battery: "battery.100"
        case .temperature: "thermometer.medium"
        case .power: "bolt"
        }
    }

    /// Hue anchor (0...1) for the metric's accent colour, kept in the kit so the
    /// app UI and the Touch Bar renderer stay in sync.
    public var hue: Double {
        switch self {
        case .cpu: 0.58     // cyan
        case .gpu: 0.78     // violet
        case .memory: 0.36  // green
        case .disk: 0.09    // amber
        case .network: 0.94 // pink
        case .fans: 0.5    // teal
        case .battery: 0.33 // green
        case .temperature: 0.03 // red-orange
        case .power: 0.14  // yellow
        }
    }

    /// Metrics enabled the first time the app runs.
    public static let defaultSelection: [MetricKind] = [.cpu, .gpu, .memory, .disk]
}
