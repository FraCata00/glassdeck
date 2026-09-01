import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Bluetooth devices")
struct BluetoothTests {
    /// A source that answers whatever the test hands it, and counts how often it
    /// was asked.
    final class StubSource: PairedDeviceSource {
        var readings: [PairedDeviceReading]?
        private(set) var reads = 0

        init(_ readings: [PairedDeviceReading]?) { self.readings = readings }

        func read() -> [PairedDeviceReading]? {
            reads += 1
            return readings
        }
    }

    private func airPods(connected: Bool = true) -> PairedDeviceReading {
        PairedDeviceReading(
            address: "2c-76-00-c6-c7-7d",
            name: "AirPods Pro",
            isConnected: connected,
            majorClass: 4,
            minorClass: 6,
            left: 94,
            right: 90,
            enclosure: 72
        )
    }

    private func mouse(connected: Bool = true, battery: Int = 55) -> PairedDeviceReading {
        PairedDeviceReading(
            address: "df-5d-fa-f4-75-53",
            name: "MX Master 3S",
            isConnected: connected,
            majorClass: 5,
            minorClass: 0x20,
            single: battery
        )
    }

    @Test("A device that reports no charge at all is left out rather than listed as n/a")
    func silentDevicesAreDropped() {
        let phone = PairedDeviceReading(address: "50-b1", name: "iPhone", isConnected: true)
        let status = BluetoothSampler.status(from: [phone, mouse()])

        #expect(status.devices.map(\.name) == ["MX Master 3S"])
        #expect(status.isAvailable)
    }

    @Test("Nothing paired means unavailable, and so does a stack that cannot be reached")
    func emptyAndMissing() {
        #expect(BluetoothSampler.status(from: []).isAvailable == false)
        #expect(BluetoothSampler.status(from: nil) == .unavailable)
    }

    @Test("A zero percentage means the device said nothing, not that it is flat")
    func zeroIsAbsence() throws {
        let status = BluetoothSampler.status(from: [mouse(battery: 0), airPods()])

        #expect(status.devices.count == 1)
        let pods = try #require(status.devices.first)
        #expect(pods.battery.single == nil)
        #expect(pods.battery.left == 0.94)
        #expect(pods.battery.enclosure == 0.72)
    }

    @Test("The emptiest battery is the one the headline shows")
    func lowestDrivesTheHeadline() {
        let status = BluetoothSampler.status(from: [airPods(), mouse(battery: 55)])

        // 72% case, 90% right, 94% left, 55% mouse.
        #expect(status.lowest == 0.55)
        #expect(status.headline == "55%")
        #expect(status.devices.first { $0.name == "AirPods Pro" }?.headline == "72%")
    }

    @Test("A disconnected device is kept, but does not count towards the headline")
    func disconnectedDevicesAreNotLive() {
        // The reading is real and stale at once: AirPods in their case go on
        // reporting the levels they were last seen at.
        let status = BluetoothSampler.status(from: [airPods(connected: false), mouse(battery: 80)])

        #expect(status.devices.count == 2)
        #expect(status.connected.map(\.name) == ["MX Master 3S"])
        #expect(status.lowest == 0.80)
        #expect(status.caption == "MX Master 3S")
    }

    @Test("With nothing connected the card says so rather than showing an old number")
    func nothingConnected() {
        let status = BluetoothSampler.status(from: [airPods(connected: false)])

        #expect(status.isAvailable)
        #expect(status.lowest == nil)
        #expect(status.headline == "n/a")
        #expect(status.caption == "nothing connected")
    }

    @Test("Connected devices sort first, and the rest by name")
    func ordering() {
        let status = BluetoothSampler.status(from: [airPods(connected: false), mouse(connected: true)])
        #expect(status.devices.map(\.name) == ["MX Master 3S", "AirPods Pro"])
    }

    @Test("Devices are recognised by class, and earbuds by the shape of their reading")
    func symbols() {
        let status = BluetoothSampler.status(from: [airPods(), mouse()])
        #expect(status.devices.first { $0.name == "AirPods Pro" }?.symbolName == "airpods.gen3")
        #expect(status.devices.first { $0.name == "MX Master 3S" }?.symbolName == "computermouse")

        // Bluetooth LE devices advertise no class at all: an unclassed device
        // with one battery is as far as the guess can go.
        let unclassed = PairedDeviceReading(address: "aa", name: "Trackpad", isConnected: true, single: 40)
        #expect(BluetoothSampler.status(from: [unclassed]).devices.first?.symbolName == "dot.radiowaves.left.and.right")

        #expect(BluetoothDevice.symbolName(major: 5, minor: 0x10, battery: .none) == "keyboard")
        #expect(BluetoothDevice.symbolName(major: 2, minor: 0, battery: .none) == "iphone")
    }

    @Test("A device with no name at all falls back to its address")
    func namelessDevice() {
        let nameless = PairedDeviceReading(address: "11-22-33", name: "", isConnected: true, single: 30)
        #expect(BluetoothSampler.status(from: [nameless]).devices.first?.name == "11-22-33")
    }

    @Test("The stack is asked at most once per query interval")
    func queriesAreThrottled() {
        let source = StubSource([mouse(battery: 50)])
        let sampler = BluetoothSampler(source: source)
        let start = Date()

        #expect(sampler.sample(at: start).headline == "50%")
        #expect(source.reads == 1)

        // Four more ticks inside the window: the cached reading comes back and
        // `bluetoothd` is left alone.
        for offset in [1.5, 3.0, 4.5, 4.9] {
            _ = sampler.sample(at: start.addingTimeInterval(offset))
        }
        #expect(source.reads == 1)

        source.readings = [mouse(battery: 45)]
        #expect(sampler.sample(at: start.addingTimeInterval(5.1)).headline == "45%")
        #expect(source.reads == 2)
    }
}
