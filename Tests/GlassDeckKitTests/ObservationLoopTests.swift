import Observation
import Testing
@testable import GlassDeckKit

/// The Touch Bar used to keep redrawing after it was switched off, because the
/// loop that fed it could not be stopped: these pin down that it now can.
@Suite("Observation loop")
@MainActor
struct ObservationLoopTests {
    @Observable
    final class Source {
        var value = 0
    }

    /// Counts the changes it is told about, and owns the loop that tells it.
    @MainActor
    final class Watcher {
        let source = Source()
        var changes = 0
        lazy var loop = ObservationLoop(self) { watcher in
            _ = watcher.source.value
        } onChange: { watcher in
            watcher.changes += 1
        }
    }

    /// The change is delivered from a task the loop hops onto the main actor,
    /// so a test has to let that task run before it looks.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("Every change is delivered while the loop runs")
    func deliversChanges() async {
        let watcher = Watcher()
        watcher.loop.start()

        watcher.source.value = 1
        await settle()
        watcher.source.value = 2
        await settle()
        #expect(watcher.changes == 2)
    }

    @Test("A stopped loop stays quiet")
    func stopSilences() async {
        let watcher = Watcher()
        watcher.loop.start()
        watcher.source.value = 1
        await settle()

        watcher.loop.stop()
        watcher.source.value = 2
        await settle()
        watcher.source.value = 3
        await settle()
        #expect(watcher.changes == 1)
    }

    @Test("Stopping and starting again does not deliver a change twice")
    func restartIsSingle() async {
        let watcher = Watcher()
        watcher.loop.start()
        // Stopped while a tracking closure is still armed: it cannot be
        // withdrawn, so it has to be ignored when it fires.
        watcher.loop.stop()
        watcher.loop.start()

        watcher.source.value = 1
        await settle()
        watcher.source.value = 2
        await settle()
        #expect(watcher.changes == 2)
    }
}
