import Foundation
import IOBluetooth

/// One paired device exactly as the Bluetooth stack describes it, before any
/// interpretation.
///
/// Percentages are whole numbers as published, where `0` means "not reported"
/// rather than "flat" — turning that into a real absence is the sampler's job.
public struct PairedDeviceReading: Sendable, Equatable {
    public var address: String
    public var name: String
    public var isConnected: Bool
    public var majorClass: UInt32
    public var minorClass: UInt32
    public var single: Int
    public var left: Int
    public var right: Int
    public var enclosure: Int

    public init(
        address: String,
        name: String,
        isConnected: Bool,
        majorClass: UInt32 = 0,
        minorClass: UInt32 = 0,
        single: Int = 0,
        left: Int = 0,
        right: Int = 0,
        enclosure: Int = 0
    ) {
        self.address = address
        self.name = name
        self.isConnected = isConnected
        self.majorClass = majorClass
        self.minorClass = minorClass
        self.single = single
        self.left = left
        self.right = right
        self.enclosure = enclosure
    }
}

/// Where the paired devices come from.
///
/// A seam, so the mapping below can be tested on a machine with nothing paired —
/// which is most of CI.
public protocol PairedDeviceSource: AnyObject {
    /// `nil` when the Bluetooth stack cannot be reached at all, which is not the
    /// same as an empty list: no hardware versus nothing paired.
    func read() -> [PairedDeviceReading]?
}

/// Battery levels of the paired Bluetooth devices.
///
/// Read-only, and nothing here needs a privilege: `NSBluetoothAlwaysUsageDescription`
/// governs CoreBluetooth, which is the framework for talking to a peripheral.
/// Asking IOBluetooth what is already paired prompts for nothing.
public final class BluetoothSampler {
    /// How often the stack is actually asked.
    ///
    /// A query costs about 0.2 ms for four devices, so this is not about time —
    /// it is a round trip to `bluetoothd`, and a battery percentage moves in
    /// minutes. At the default cadence this turns one wake-up per 1.5 s into one
    /// per 5 s and loses nothing observable.
    public static let queryInterval: TimeInterval = 5

    private let source: any PairedDeviceSource
    private var cached: BluetoothStatus = .unavailable
    private var lastQuery: Date?

    public init(source: any PairedDeviceSource = IOBluetoothPairedDeviceSource()) {
        self.source = source
    }

    public func sample(at now: Date) -> BluetoothStatus {
        if let lastQuery, now.timeIntervalSince(lastQuery) < Self.queryInterval {
            return cached
        }
        lastQuery = now
        cached = Self.status(from: source.read())
        return cached
    }

    /// Turns raw readings into what the UI shows.
    ///
    /// Devices that report no charge at all are dropped rather than listed as
    /// "n/a": a paired speaker or a car stereo would otherwise sit in the card
    /// for good, and this module is about batteries.
    static func status(from readings: [PairedDeviceReading]?) -> BluetoothStatus {
        guard let readings else { return .unavailable }

        let devices = readings.compactMap { reading -> BluetoothDevice? in
            let battery = BluetoothBattery(
                single: level(reading.single),
                left: level(reading.left),
                right: level(reading.right),
                enclosure: level(reading.enclosure)
            )
            guard !battery.isEmpty else { return nil }
            return BluetoothDevice(
                address: reading.address,
                name: reading.name.isEmpty ? reading.address : reading.name,
                isConnected: reading.isConnected,
                battery: battery,
                symbolName: BluetoothDevice.symbolName(
                    major: reading.majorClass,
                    minor: reading.minorClass,
                    battery: battery
                )
            )
        }
        // Connected first, then by name, so the list does not reshuffle itself
        // every time a percentage changes.
        .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }

        return BluetoothStatus(devices: devices, isAvailable: !devices.isEmpty)
    }

    /// `0` is how the stack says "I have no reading", and percentages above 100
    /// have been seen from devices that count in tenths.
    private static func level(_ percent: Int) -> Double? {
        guard percent > 0 else { return nil }
        return (Double(percent) / 100).clamped01
    }
}

/// The live source: `IOBluetoothDevice.pairedDevices()`.
public final class IOBluetoothPairedDeviceSource: PairedDeviceSource {
    /// The battery keys, in the order the model wants them.
    ///
    /// These are undocumented KVC properties of `IOBluetoothDevice` — there is no
    /// public API for a paired device's charge, and this is the same door the
    /// system's own Bluetooth menu goes through. Every access is guarded by
    /// `responds(to:)` because `value(forKey:)` on a key that has gone away
    /// raises an Objective-C exception, which Swift cannot catch: the guard is
    /// what turns a future macOS removing these into a module that reports
    /// nothing instead of a crashing menu bar.
    private static let batteryKeys = ["batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight", "batteryPercentCase"]

    public init() {}

    public func read() -> [PairedDeviceReading]? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }

        return paired.map { device in
            let levels = Self.batteryKeys.map { key -> Int in
                guard device.responds(to: NSSelectorFromString(key)) else { return 0 }
                return (device.value(forKey: key) as? NSNumber)?.intValue ?? 0
            }
            return PairedDeviceReading(
                address: device.addressString ?? "",
                name: device.name ?? "",
                isConnected: device.isConnected(),
                majorClass: device.deviceClassMajor,
                minorClass: device.deviceClassMinor,
                single: levels[0],
                left: levels[1],
                right: levels[2],
                enclosure: levels[3]
            )
        }
    }
}
