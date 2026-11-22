import Darwin
import Foundation
import Testing
@testable import GlassDeckKit

/// `proc_taskinfo` reports CPU time in Mach ticks. Before these, the ticks were
/// read as nanoseconds, which on Apple silicon put every process at 1/41.7 of
/// its real load.
@Suite("Process CPU time")
struct ProcessSamplerTests {
    @Test("Ticks are scaled by the timebase")
    func ticksAreScaled() {
        // Apple silicon's timebase, and the figures measured on it.
        let seconds = ProcessSampler.seconds(ofTicks: 7_195_286, timebase: (125, 3))
        #expect(abs(seconds - 0.2998) < 0.001)
        // Intel's timebase is one nanosecond per tick.
        #expect(ProcessSampler.seconds(ofTicks: 1_500_000_000, timebase: (1, 1)) == 1.5)
    }

    @Test("The converted counters agree with this process's own CPU clock")
    func agreesWithTheCPUClock() {
        let sampler = ProcessSampler()

        func ticks() -> UInt64 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, size) == size else { return 0 }
            return info.pti_total_user + info.pti_total_system
        }

        let startTicks = ticks()
        let startClock = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
        var sink = 0.0
        for value in 0..<3_000_000 { sink += Double(value).squareRoot() }
        let endTicks = ticks()
        let endClock = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)

        let measured = Double(endClock - startClock) / 1_000_000_000
        let converted = ProcessSampler.seconds(ofTicks: endTicks - startTicks, timebase: sampler.timebase)

        #expect(sink > 0)
        // Other test threads share the process clock, so only the scale is
        // asserted: the bug was a factor of forty, not a few per cent.
        #expect(converted > measured * 0.5 && converted < measured * 2)
    }
}
