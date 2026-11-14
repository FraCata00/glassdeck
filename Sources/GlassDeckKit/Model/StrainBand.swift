import Foundation

/// How close a metric is to trouble, in the three bands every status colour
/// uses — the scale of `MetricsSnapshot.strain(for:)`.
///
/// The thresholds used to be written out in each place that tinted something;
/// they live here so the Touch Bar's signal style and the panel's dots cannot
/// drift apart.
public enum StrainBand: Sendable, Equatable {
    case calm
    case elevated
    case high

    public init(strain: Double) {
        switch strain {
        case ..<0.7: self = .calm
        case ..<0.88: self = .elevated
        default: self = .high
        }
    }
}

extension MetricKind {
    /// How long a reading is kept before the SMC is asked again, for the
    /// metrics that cost a kernel round trip per key; `nil` for the rest.
    /// Read from the samplers so the settings cannot quote a stale figure.
    public var smcCacheInterval: TimeInterval? {
        switch self {
        case .temperature: ThermalSampler.refreshInterval
        case .fans: FanSampler.refreshInterval
        case .power: PowerSampler.refreshInterval
        case .cpu, .gpu, .memory, .disk, .network, .battery: nil
        }
    }
}
