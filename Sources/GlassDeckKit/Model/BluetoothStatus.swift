import Foundation

/// What a paired device reports about its charge.
///
/// Every field is a fraction in `0...1`, or `nil` when the device does not
/// publish that one. The distinction matters: the Bluetooth stack reports an
/// absent reading as `0`, and a mouse that is out of battery and a mouse that
/// simply never says look identical unless they are told apart here.
public struct BluetoothBattery: Sendable, Equatable {
    /// The single level published by a device with one battery — a mouse, a
    /// keyboard, a game controller.
    public var single: Double?
    /// The two earbuds and the charging case, for the devices that split them.
    public var left: Double?
    public var right: Double?
    public var enclosure: Double?

    public init(single: Double? = nil, left: Double? = nil, right: Double? = nil, enclosure: Double? = nil) {
        self.single = single
        self.left = left
        self.right = right
        self.enclosure = enclosure
    }

    public static let none = BluetoothBattery()

    public var isEmpty: Bool { levels.isEmpty }

    /// Every reading the device publishes, paired with its label.
    public var levels: [(label: String, value: Double)] {
        var items: [(String, Double)] = []
        if let single { items.append((L.t("bluetooth.battery", "battery"), single)) }
        if let left { items.append((L.t("bluetooth.left", "left"), left)) }
        if let right { items.append((L.t("bluetooth.right", "right"), right)) }
        if let enclosure { items.append((L.t("bluetooth.case", "case"), enclosure)) }
        return items
    }

    /// The reading that decides whether the device needs charging — the emptiest
    /// one. A pair of earbuds is as usable as its flatter half.
    public var lowest: Double? { levels.map(\.value).min() }

    public var headline: String {
        guard let lowest else { return L.t("value.na", "n/a") }
        return ValueFormatter.percent(lowest)
    }
}

/// One paired Bluetooth device.
public struct BluetoothDevice: Sendable, Equatable, Identifiable {
    /// The MAC address, which is the only identifier that survives a rename.
    public var address: String
    public var name: String
    public var isConnected: Bool
    public var battery: BluetoothBattery
    public var symbolName: String

    public init(
        address: String,
        name: String,
        isConnected: Bool,
        battery: BluetoothBattery = .none,
        symbolName: String = "dot.radiowaves.left.and.right"
    ) {
        self.address = address
        self.name = name
        self.isConnected = isConnected
        self.battery = battery
        self.symbolName = symbolName
    }

    public var id: String { address }

    public var headline: String { battery.headline }

    /// SF Symbol for a device, from the class of device it advertises.
    ///
    /// Bluetooth LE devices — which is most of what carries a battery now —
    /// advertise no class at all and come through as `0/0`: measured here, only
    /// the AirPods reported one (major 4, minor 6), while an iPhone, an iPad and
    /// an MX Master all reported nothing. So the shape of the battery reading is
    /// the second witness: left, right and a case can only be a pair of earbuds.
    public static func symbolName(major: UInt32, minor: UInt32, battery: BluetoothBattery) -> String {
        if battery.left != nil || battery.right != nil || battery.enclosure != nil { return "airpods.gen3" }
        switch major {
        case 1: return "laptopcomputer"
        case 2: return "iphone"
        case 4: return "headphones"
        case 5:
            // Peripheral minor class is a bit field: 0x10 keyboard, 0x20 pointing.
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "dot.radiowaves.left.and.right"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Every paired device worth showing, or a marker that there is nothing to show.
///
/// Devices with no battery reading at all are dropped by the sampler: a paired
/// speaker that never reports a charge would otherwise be a permanent row
/// reading "n/a".
public struct BluetoothStatus: Sendable, Equatable {
    public var devices: [BluetoothDevice]
    /// `false` when nothing paired reports a battery, or when the Bluetooth
    /// stack cannot be reached at all.
    public var isAvailable: Bool

    public init(devices: [BluetoothDevice] = [], isAvailable: Bool = false) {
        self.devices = devices
        self.isAvailable = isAvailable
    }

    public static let unavailable = BluetoothStatus()

    /// The devices that are actually on the air right now.
    ///
    /// This is the split the whole module turns on. A disconnected device keeps
    /// publishing the last percentage it was seen at, indefinitely and with
    /// nothing to mark it stale — a pair of AirPods sitting in their case here
    /// went on reporting 94 / 90 / 72 hours later. Those numbers are not wrong,
    /// they are just old, so they are shown as belonging to a device that is not
    /// connected rather than mixed in with live ones.
    public var connected: [BluetoothDevice] { devices.filter(\.isConnected) }

    /// The emptiest battery among the connected devices: what the card's
    /// headline shows, because it is the one that will need a cable first.
    public var lowest: Double? { connected.compactMap(\.battery.lowest).min() }

    public var headline: String {
        guard let lowest else { return L.t("value.na", "n/a") }
        return ValueFormatter.percent(lowest)
    }

    public var caption: String {
        guard isAvailable else { return L.t("bluetooth.none", "no devices") }
        let count = connected.count
        guard count > 0 else { return L.t("bluetooth.disconnected", "nothing connected") }
        return count == 1
            ? (connected[0].name)
            : L.t("bluetooth.count", "%lld devices", count)
    }
}
