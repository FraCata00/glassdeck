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
    public private(set) var topProcesses: [ProcessSample] = []
    public private(set) var isRunning = false

    /// Seconds between samples. Changing it restarts the loop.
    public var interval: TimeInterval {
        didSet {
            guard interval != oldValue, isRunning else { return }
            restart()
        }
    }

    /// True while at least one view showing the process list is on screen; keeps
    /// the process scan off the hot path otherwise.
    public private(set) var samplesProcesses = false

    /// How many views currently want the process list.
    ///
    /// Counted rather than flagged: the menu bar panel and the dashboard can be
    /// open at the same time, and whichever of them closes first must not switch
    /// the scan off under the other.
    private var processObservers = 0

    private var history: [MetricKind: RingBuffer<Double>] = [:]
    private let engine = MetricsEngine()
    private var task: Task<Void, Never>?

    public init(interval: TimeInterval = 1.5) {
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
        restart()
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Takes one sample immediately, outside the loop cadence.
    public func refreshNow() async {
        await ingest(await engine.sample())
    }

    private func restart() {
        task?.cancel()
        let interval = interval
        task = Task { [weak self] in
            // A leading sample makes the window feel instant when it opens.
            // The loop owns no strong reference, so it retires on its own once
            // the monitor is deallocated.
            await self?.refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        let snapshot = await engine.sample()
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
    }
}
