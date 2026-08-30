import Foundation

/// Reads fan speeds from the SMC.
///
/// The fan count and each fan's rated range are static, so they are read once;
/// only the live RPM is polled on every sample.
public final class FanSampler {
    private let smc: SMCService?
    private let descriptors: [(index: Int, minimum: Double, maximum: Double)]

    public init() {
        smc = SMCService()

        guard let smc, let count = smc.readNumber("FNum"), count > 0 else {
            descriptors = []
            return
        }

        descriptors = (0..<Int(count)).map { index in
            (
                index: index,
                minimum: smc.readNumber("F\(index)Mn") ?? 0,
                maximum: smc.readNumber("F\(index)Mx") ?? 6000
            )
        }
    }

    public func sample() -> FanUsage {
        guard let smc, !descriptors.isEmpty else { return .unavailable }

        let fans = descriptors.map { descriptor in
            Fan(
                index: descriptor.index,
                rpm: smc.readNumber("F\(descriptor.index)Ac") ?? 0,
                minimumRPM: descriptor.minimum,
                maximumRPM: descriptor.maximum
            )
        }
        return FanUsage(fans: fans, isAvailable: true)
    }
}
