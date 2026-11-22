import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Touch Bar styles")
struct TouchBarStyleTests {
    @Test("Every style is stored by a stable raw value")
    func rawValuesRoundTrip() {
        for style in TouchBarStyle.allCases {
            #expect(TouchBarStyle(rawValue: style.rawValue) == style)
            #expect(!style.title.isEmpty)
            #expect(!style.summary.isEmpty)
        }
        // A rename here would silently reset everyone's choice to the default.
        #expect(TouchBarStyle.glass.rawValue == "glass")
    }

    @Test("Strain bands break at 0.7 and 0.88, as the status tints always have")
    func strainBands() {
        #expect(StrainBand(strain: 0) == .calm)
        #expect(StrainBand(strain: 0.69) == .calm)
        #expect(StrainBand(strain: 0.7) == .elevated)
        #expect(StrainBand(strain: 0.879) == .elevated)
        #expect(StrainBand(strain: 0.88) == .high)
        #expect(StrainBand(strain: 1.4) == .high)
    }

    @Test("A low reading lights one segment, never none, and a full one lights them all")
    func litSegments() {
        #expect(TouchBarHistory.litSegments(0, count: 10) == 0)
        #expect(TouchBarHistory.litSegments(0.01, count: 10) == 1)
        #expect(TouchBarHistory.litSegments(0.23, count: 10) == 2)
        #expect(TouchBarHistory.litSegments(0.26, count: 10) == 3)
        #expect(TouchBarHistory.litSegments(1, count: 10) == 10)
        #expect(TouchBarHistory.litSegments(3, count: 10) == 10)
        #expect(TouchBarHistory.litSegments(0.5, count: 0) == 0)
    }

    @Test("A nearly flat history is zoomed into a window 8 points tall")
    func flatHistoryZooms() {
        let window = TouchBarHistory.window(for: [0.70, 0.71, 0.705])
        #expect(abs((window.upperBound - window.lowerBound) - 0.08) < 1e-9)
        #expect(window.contains(0.70) && window.contains(0.71))
    }

    @Test("A history flat at either end of the scale is drawn at that end")
    func flatHistoryAtTheEdges() {
        let full = TouchBarHistory.window(for: [1, 1, 1])
        #expect(full.upperBound <= 1)
        #expect(TouchBarHistory.normalised(1, in: full) == 1)

        let empty = TouchBarHistory.window(for: [0, 0, 0])
        #expect(empty.lowerBound >= 0)
        #expect(TouchBarHistory.normalised(0, in: empty) == 0)
    }

    @Test("Columns keep only the latest samples and never draw an empty one")
    func columns() {
        let history = (0..<40).map { Double($0) / 39 }
        let columns = TouchBarHistory.columns(history, count: 16)
        #expect(columns.count == 16)
        #expect(columns.last == 1)
        #expect(columns.allSatisfy { $0 >= 0.08 && $0 <= 1 })
        #expect(TouchBarHistory.columns([], count: 16).isEmpty)
        #expect(TouchBarHistory.columns([0.4, 0.5], count: 16).count == 2)
    }

    @Test("The terminal line keeps the title while it fits, then gives the rest to the sparkline")
    func terminalLine() {
        let history = (0..<40).map { Double($0) / 39 }
        let wide = TouchBarHistory.terminalLine(title: "RAM", candidates: ["9.8 GB", "71%"], history: history, characters: 20)
        #expect(wide.title == "RAM")
        #expect(wide.headline == "9.8 GB")
        #expect(wide.sparkline.count == 8)

        // "RAM 9.8 GB" is ten characters: no room for three blocks in twelve.
        let snug = TouchBarHistory.terminalLine(title: "RAM", candidates: ["9.8 GB", "71%"], history: history, characters: 12)
        #expect(snug.headline == "9.8 GB")
        #expect(snug.sparkline.isEmpty)

        let shorter = TouchBarHistory.terminalLine(title: "RAM", candidates: ["9.8 GB", "71%"], history: history, characters: 8)
        #expect(shorter.title == "RAM")
        #expect(shorter.headline == "71%")

        let cramped = TouchBarHistory.terminalLine(title: "RAM", candidates: ["9.8 GB", "71%"], history: history, characters: 5)
        #expect(cramped.title == nil)
        #expect(cramped.headline == "71%")
    }

    @Test("Narrow panels get fewer segments and columns")
    func counts() {
        #expect(TouchBarHistory.meterSegmentCount(width: 60) == 10)
        #expect(TouchBarHistory.meterSegmentCount(width: 30) == 6)
        #expect(TouchBarHistory.columnCount(width: 90) == 16)
        #expect(TouchBarHistory.columnCount(width: 30) == 10)
        #expect(TouchBarHistory.columnCount(width: 1) == 1)
    }

    @Test("Only the SMC-backed metrics report a cache interval")
    func smcCacheIntervals() {
        #expect(MetricKind.temperature.smcCacheInterval == 5)
        #expect(MetricKind.fans.smcCacheInterval == 3)
        #expect(MetricKind.power.smcCacheInterval == 2)
        #expect(MetricKind.cpu.smcCacheInterval == nil)
    }

    @Test("The character sparkline runs from the lowest block to the highest")
    func sparkline() {
        let line = TouchBarHistory.sparkline([0, 0.25, 0.5, 0.75, 1], count: 8)
        #expect(line.count == 5)
        #expect(line.first == "▁")
        #expect(line.last == "█")
        #expect(TouchBarHistory.sparkline([], count: 8).isEmpty)
    }
}
