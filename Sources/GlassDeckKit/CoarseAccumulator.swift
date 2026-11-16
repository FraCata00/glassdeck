import Foundation

/// Folds every sample taken between two `coarseSnapshot` publications into the
/// one that is published.
///
/// The coarse snapshot used to be whichever sample happened to land after the
/// throttle opened. At the default 1.5 s cadence against a 2 s throttle that is
/// every other sample, so the menu bar spent three seconds showing a reading
/// that covered the last 1.5 of them: half the machine's activity never reached
/// it, and a burst inside the dropped sample was simply not there. Activity
/// Monitor averages over its whole update period, which is why the two
/// disagreed.
///
/// What is averaged are the rates — CPU and GPU load, disk and network
/// throughput — each weighted by the time its sample covers, which for the
/// tick-delta metrics is exactly the reading one long sample would have given.
/// Levels (memory, temperature, charge, capacity) are a state rather than a
/// rate, so the latest reading is the right one and is passed through.
struct CoarseAccumulator {
    /// The longest span a single sample is weighted for.
    ///
    /// The first sample after display sleep covers however long the screen was
    /// dark. Weighted for all of it, it would outweigh every ordinary tick in
    /// its window by a thousand to one; capped, it counts as a long tick.
    static let maximumSpan: TimeInterval = 10

    private var latest: MetricsSnapshot?
    private var previousTimestamp: Date?

    private var weight = 0.0
    private var cpu = (user: 0.0, system: 0.0, nice: 0.0, idle: 0.0)
    private var perCore: [Double] = []
    private var perCoreIsConsistent = true
    private var gpu = (device: 0.0, renderer: 0.0, tiler: 0.0)
    private var disk = (read: 0.0, write: 0.0)
    private var network = (down: 0.0, up: 0.0)
    private var count = 0

    mutating func add(_ snapshot: MetricsSnapshot) {
        let span = previousTimestamp.map { snapshot.timestamp.timeIntervalSince($0) } ?? 0
        previousTimestamp = snapshot.timestamp
        latest = snapshot
        count += 1

        // A sample with no known span — the very first — still has to count
        // for something, or a window holding only it would divide by zero.
        let w = span > 0 ? min(span, Self.maximumSpan) : 1
        weight += w

        cpu.user += snapshot.cpu.user * w
        cpu.system += snapshot.cpu.system * w
        cpu.nice += snapshot.cpu.nice * w
        cpu.idle += snapshot.cpu.idle * w

        if count == 1 {
            perCore = snapshot.cpu.perCore.map { $0 * w }
        } else if perCore.count == snapshot.cpu.perCore.count {
            for index in perCore.indices { perCore[index] += snapshot.cpu.perCore[index] * w }
        } else {
            perCoreIsConsistent = false
        }

        gpu.device += snapshot.gpu.utilisation * w
        gpu.renderer += snapshot.gpu.rendererUtilisation * w
        gpu.tiler += snapshot.gpu.tilerUtilisation * w
        disk.read += snapshot.disk.readBytesPerSecond * w
        disk.write += snapshot.disk.writeBytesPerSecond * w
        network.down += snapshot.network.downloadBytesPerSecond * w
        network.up += snapshot.network.uploadBytesPerSecond * w
    }

    /// The snapshot to publish, and a fresh window for the next one.
    ///
    /// A window of one sample is returned untouched, so nothing changes for a
    /// cadence slower than the throttle.
    mutating func drain() -> MetricsSnapshot {
        defer { reset() }
        guard var result = latest else { return .empty }
        guard count > 1, weight > 0 else { return result }

        result.cpu.user = cpu.user / weight
        result.cpu.system = cpu.system / weight
        result.cpu.nice = cpu.nice / weight
        result.cpu.idle = cpu.idle / weight
        // A core count that changed mid-window has no meaningful mean; the
        // latest sample's own figures stand in.
        if perCoreIsConsistent { result.cpu.perCore = perCore.map { $0 / weight } }

        result.gpu.utilisation = gpu.device / weight
        result.gpu.rendererUtilisation = gpu.renderer / weight
        result.gpu.tilerUtilisation = gpu.tiler / weight
        result.disk.readBytesPerSecond = disk.read / weight
        result.disk.writeBytesPerSecond = disk.write / weight
        result.network.downloadBytesPerSecond = network.down / weight
        result.network.uploadBytesPerSecond = network.up / weight
        return result
    }

    /// Clears the window but keeps the last timestamp, so the next sample's
    /// span is measured from the one just published.
    private mutating func reset() {
        let timestamp = previousTimestamp
        self = CoarseAccumulator()
        previousTimestamp = timestamp
    }
}
