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

    /// Set while the dashboard is visible; keeps the process scan off the hot path otherwise.
    public var samplesProcesses = false

    private var history: [MetricKind: RingBuffer<Double>] = [:]
    private let engine = MetricsEngine()
    private var task: Task<Void, Never>?

    public init(interval: TimeInterval = 1.5) {
        self.interval = interval
        for kind in MetricKind.allCases {
            history[kind] = RingBuffer<Double>(capacity: Self.historyLength)
        }
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
