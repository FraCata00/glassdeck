import Foundation
import Observation

/// The observable façade the UI binds to: it drives the sampling loop, keeps a
/// rolling history for the sparklines and republishes everything on the main actor.
@MainActor
@Observable
public final class SystemMonitor {
    /// How many samples the sparklines keep. At the default cadence this is about a minute of history.
    public static let historyLength = 60

    public private(set) var snapshot: MetricsSnapshot = .empty

    /// The same reading, republished on a slower cadence for surfaces whose
    /// redraw costs more than the freshness buys.
    ///
    /// The menu bar status item is the case this exists for. Updating it costs
    /// about 22 ms of CPU every time — profiling the running app found it to be
    /// the single largest cost, well above all the sampling — for a glyph 15 pt
    /// tall. Because `@Observable` tracks each property separately, a view that
    /// reads this and not `snapshot` is invalidated only when this is assigned.
    public private(set) var coarseSnapshot: MetricsSnapshot = .empty

    /// Shortest gap between two `coarseSnapshot` publications. At the default
    /// cadence this halves how often the status item is redrawn.
    public static let coarseInterval: TimeInterval = 2
    public private(set) var topProcesses: [ProcessSample] = []
    public private(set) var isRunning = false

    /// The cadence a fresh install samples at.
    public static let defaultInterval: TimeInterval = 1.5

    /// Seconds between samples. Changing it restarts the loop.
    public var interval: TimeInterval {
        didSet {
            guard interval != oldValue, isRunning else { return }
            restart()
        }
    }

    /// What the interval is multiplied by while macOS is in Low Power Mode.
    ///
    /// Low Power Mode is the user saying the battery matters more than anything
    /// on screen right now, and a system monitor is the last thing that should
    /// argue. Doubling is enough to halve the sampling cost without the graphs
    /// becoming a different shape.
    public static let lowPowerMultiplier: TimeInterval = 2

    /// True while macOS is in Low Power Mode.
    ///
    /// Read fresh rather than cached from a notification: the loop asks for it
    /// once per tick anyway, which is far less often than the state can change.
    public var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// The gap the loop actually sleeps for.
    public var effectiveInterval: TimeInterval {
        isLowPowerModeEnabled ? interval * Self.lowPowerMultiplier : interval
    }

    /// True while sampling is parked because nobody can see the result — the
    /// display is asleep, the machine is suspended, or another user is in front.
    ///
    /// Distinct from `isRunning`, which records whether the app wants to be
    /// sampling at all: parking has to be undone by `resume()` without losing
    /// that intent.
    public private(set) var isSuspended = false

    /// Whether the paired Bluetooth devices are sampled at all.
    ///
    /// Off until the module is switched on: the first question asked of the
    /// Bluetooth stack is what triggers the system's permission prompt, and
    /// nobody should be asked for a permission by an app they have not asked
    /// for the feature.
    public var samplesBluetooth = false

    /// True while at least one view showing the process list is on screen; keeps
    /// the process scan off the hot path otherwise.
    public private(set) var samplesProcesses = false

    /// How many views currently want the process list.
    ///
    /// Counted rather than flagged: the menu bar panel and the dashboard can be
    /// open at the same time, and whichever of them closes first must not switch
    /// the scan off under the other.
    private var processObservers = 0

    private var lastCoarsePublish: Date?
    private var history: [MetricKind: RingBuffer<Double>] = [:]
    private let engine = MetricsEngine()
    private var task: Task<Void, Never>?
    private var powerSources: PowerSourceObserver?

    public init(interval: TimeInterval = SystemMonitor.defaultInterval) {
        self.interval = interval
        for kind in MetricKind.allCases {
            history[kind] = RingBuffer<Double>(capacity: Self.historyLength)
        }
    }

    /// Registers interest in the process list. Balance every call with
    /// `endSamplingProcesses()`.
    public func beginSamplingProcesses() {
        processObservers += 1
        samplesProcesses = true
    }

    public func endSamplingProcesses() {
        processObservers = max(0, processObservers - 1)
        samplesProcesses = processObservers > 0
    }

    /// Rolling history for a metric, oldest sample first.
    public func history(for kind: MetricKind) -> [Double] {
        history[kind]?.values ?? []
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let powerSources = PowerSourceObserver { [weak self] in
            Task { await self?.refreshBattery() }
        }
        powerSources.start()
        self.powerSources = powerSources
        restart()
    }

    public func stop() {
        powerSources?.stop()
        powerSources = nil
        task?.cancel()
        task = nil
        isRunning = false
        isSuspended = false
    }

    /// Parks the loop without clearing the intent to be running.
    ///
    /// There is nothing to show while the display is asleep, so polling the SMC
    /// into a dark screen buys nothing and costs a wake-up every tick.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        task?.cancel()
        task = nil
    }

    /// Undoes `suspend()`. The loop takes a leading sample straight away, so the
    /// first thing seen after a wake is a fresh reading rather than the one from
    /// before the display went dark.
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        restart()
    }

    /// Takes one sample immediately, outside the loop cadence.
    public func refreshNow() async {
        await ingest(await engine.sample(bluetooth: samplesBluetooth))
    }

    /// Re-reads the battery alone, straight after macOS reports a power-source
    /// change, instead of leaving it to the next tick.
    public func refreshBattery() async {
        guard isRunning, !isSuspended else { return }
        applyBattery(await engine.sampleBattery())
    }

    /// Patches a fresh battery reading into both snapshots, bypassing the coarse
    /// throttle: plugging the adapter in is the one change worth redrawing the
    /// status item and the mini bar for at once. The history is left alone so
    /// the sparklines keep their cadence.
    func applyBattery(_ battery: BatteryUsage) {
        // Nothing published yet: the leading sample is on its way and will
        // carry the reading anyway.
        guard snapshot != .empty else { return }
        if snapshot.battery != battery { snapshot.battery = battery }
        if coarseSnapshot != .empty, coarseSnapshot.battery != battery {
            coarseSnapshot.battery = battery
        }
    }

    private func restart() {
        task?.cancel()
        task = nil
        guard isRunning, !isSuspended else { return }

        task = Task { [weak self] in
            // A leading sample makes the window feel instant when it opens.
            // The loop owns no strong reference, so it retires on its own once
            // the monitor is deallocated.
            await self?.refreshNow()
            while !Task.isCancelled {
                // Read once per iteration rather than captured up front, so Low
                // Power Mode is picked up at the next tick without the loop
                // having to be torn down and rebuilt to notice.
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.effectiveInterval))
                guard !Task.isCancelled else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        let snapshot = await engine.sample(bluetooth: samplesBluetooth)
        await ingest(snapshot)

        if samplesProcesses {
            topProcesses = await engine.topProcesses()
        } else if !topProcesses.isEmpty {
            topProcesses = []
        }
    }

    private func ingest(_ snapshot: MetricsSnapshot) async {
        self.snapshot = snapshot
        for kind in MetricKind.allCases {
            history[kind]?.append(snapshot.fraction(for: kind))
        }

        // Held back until enough time has passed, so the expensive surfaces are
        // not redrawn at the sampling cadence. Sampling faster than the coarse
        // interval speeds up the graphs without speeding up the status item.
        if let lastCoarsePublish,
           snapshot.timestamp.timeIntervalSince(lastCoarsePublish) < Self.coarseInterval {
            return
        }
        lastCoarsePublish = snapshot.timestamp
        coarseSnapshot = snapshot
    }
}
