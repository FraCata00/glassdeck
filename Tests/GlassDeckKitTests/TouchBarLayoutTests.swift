import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Touch Bar layout")
struct TouchBarLayoutTests {
    private static let batteryWidth: CGFloat = 62
    private static let miniMeterWidth: CGFloat = 120

    private func layout(
        _ mode: TouchBarMode,
        selection: [MetricKind] = MetricKind.defaultSelection,
        order: [MetricKind] = MetricKind.allCases,
        supported: Set<MetricKind> = Set(MetricKind.allCases),
        hasBattery: Bool = true,
        alignment: TouchBarAlignment = .trailing,
        miniMeterWidth: CGFloat = Self.miniMeterWidth
    ) -> TouchBarLayout {
        TouchBarLayout(
            mode: mode,
            selection: selection,
            order: order,
            supported: supported,
            hasBattery: hasBattery,
            alignment: alignment,
            batteryWidth: Self.batteryWidth,
            miniMeterWidth: miniMeterWidth
        )
    }

    /// Everything on the bar, measured the way the system lays it out.
    private func width(of layout: TouchBarLayout) -> CGFloat {
        let content = layout.items.filter { $0 != .flexibleSpace }
        let items = content.reduce(CGFloat(0)) { total, item in
            switch item {
            case .leadingSpacer: total + layout.leadingSpacerWidth
            case .metric: total + layout.panelWidth
            case .battery: total + Self.batteryWidth
            case .miniMeter: total + Self.miniMeterWidth
            case .grow, .collapse, .dashboard: total + TouchBarLayout.controlWidth
            default: total
            }
        }
        return items + CGFloat(content.count - 1) * TouchBarLayout.itemSpacing
    }

    @Test("The shared bar holds at most four panels and leaves the hardware readings out")
    func expandedCapsPanels() {
        let bar = layout(.expanded, selection: MetricKind.allCases)
        #expect(bar.metrics == [.cpu, .gpu, .memory, .disk])
        #expect(bar.panelWidth == TouchBarLayout.minimumPanelWidth)
        #expect(bar.items.suffix(4) == [.battery, .grow, .collapse, .flexibleSpace])
        #expect(!bar.items.contains(.dashboard))
    }

    @Test("The shared bar never runs under the Control Strip")
    func expandedFitsSharedRegion() {
        for alignment in TouchBarAlignment.allCases {
            let bar = layout(.expanded, selection: MetricKind.allCases, alignment: alignment)
            #expect(width(of: bar) <= TouchBarLayout.sharedRegionWidth)
        }
    }

    @Test("Full width adds the fans and temperature the machine has, in the user's order")
    func fullscreenAddsExtras() {
        let order: [MetricKind] = [.temperature, .cpu, .memory, .fans, .gpu, .disk, .network, .battery, .power]
        let bar = layout(.fullscreen, selection: [.cpu, .memory, .battery], order: order)
        #expect(bar.metrics == [.temperature, .cpu, .memory, .fans])
    }

    @Test("Full width leaves out what the machine cannot report")
    func fullscreenDropsUnsupported() {
        let bar = layout(
            .fullscreen,
            selection: [.cpu, .gpu],
            supported: [.cpu, .memory, .disk, .network, .temperature]
        )
        #expect(bar.metrics == [.cpu, .temperature])
    }

    @Test("Full width has a dashboard button and no grow button")
    func fullscreenControls() {
        let bar = layout(.fullscreen)
        #expect(bar.items.suffix(3) == [.battery, .dashboard, .collapse])
        #expect(!bar.items.contains(.grow))
        #expect(bar.leadingSpacerWidth == 0)
        #expect(!bar.items.contains(.flexibleSpace))
    }

    @Test("Full-width panels stretch to fill the bar without overflowing it", arguments: [true, false])
    func fullscreenFillsBar(hasBattery: Bool) {
        for count in 1...7 {
            let selection = Array(MetricKind.allCases.filter { $0 != .battery && $0 != .power }.prefix(count))
            let bar = layout(
                .fullscreen,
                selection: selection,
                supported: Set(selection).union([.cpu, .gpu, .memory, .disk, .network]),
                hasBattery: hasBattery
            )
            let used = width(of: bar)
            #expect(used <= TouchBarLayout.fullRegionWidth)
            // Rounding each panel down loses less than a point apiece.
            #expect(used > TouchBarLayout.fullRegionWidth - CGFloat(bar.metrics.count))
        }
    }

    @Test("The battery chip appears only on a Mac with a battery")
    func batteryChip() {
        #expect(layout(.expanded, hasBattery: true).items.contains(.battery))
        #expect(!layout(.expanded, hasBattery: false).items.contains(.battery))
        #expect(!layout(.fullscreen, hasBattery: false).items.contains(.battery))
    }

    @Test("Battery and power are never panels")
    func batteryAndPowerNotPanels() {
        for mode in [TouchBarMode.expanded, .fullscreen] {
            let bar = layout(mode, selection: [.battery, .power, .cpu])
            #expect(!bar.metrics.contains(.battery))
            #expect(!bar.metrics.contains(.power))
        }
    }

    @Test("The mini bar is the meter and its two buttons")
    func mini() {
        let bar = layout(.mini, alignment: .leading)
        #expect(bar.items == [.miniMeter, .grow, .collapse, .flexibleSpace])
        #expect(bar.metrics.isEmpty)
    }

    @Test("The detail bar is the metric between back and collapse")
    func detail() {
        let bar = layout(.detail(.gpu))
        #expect(bar.items == [.back, .detail, .collapse])
        #expect(bar.leadingSpacerWidth == 0)
    }

    @Test("Nothing is laid out while collapsed")
    func collapsed() {
        #expect(layout(.collapsed).items.isEmpty)
    }

    @Test("Right alignment pushes the bar against the Control Strip")
    func trailingAlignment() {
        let bar = layout(.expanded, selection: [.cpu], alignment: .trailing)
        #expect(bar.items.first == .leadingSpacer)
        // The spacer is an item like any other, so the system puts a gap after
        // it too: the bar ends at the region's edge only once that is counted.
        #expect(width(of: bar) == TouchBarLayout.sharedRegionWidth)
    }

    @Test("Centring leaves the same room on either side", arguments: [[MetricKind.cpu], [.cpu, .gpu, .memory]])
    func centreAlignment(selection: [MetricKind]) {
        let centred = layout(.expanded, selection: selection, alignment: .center)
        let unshifted = layout(.expanded, selection: selection, alignment: .leading)
        let before = centred.leadingSpacerWidth + TouchBarLayout.itemSpacing
        let after = TouchBarLayout.sharedRegionWidth - width(of: centred)
        #expect(before == after)
        #expect(width(of: centred) - before == width(of: unshifted))
    }

    @Test("Right alignment ends at the region's edge for the mini bar too")
    func trailingMini() {
        let bar = layout(.mini, alignment: .trailing)
        #expect(bar.items.first == .leadingSpacer)
        #expect(width(of: bar) == TouchBarLayout.sharedRegionWidth)
    }

    @Test("Left alignment uses no spacer")
    func leadingAlignment() {
        let bar = layout(.expanded, selection: [.cpu], alignment: .leading)
        #expect(bar.items.first == .metric(.cpu))
        #expect(bar.items.last == .flexibleSpace)
        #expect(bar.leadingSpacerWidth == 0)
    }

    @Test("A bar with almost no room to spare is not shifted")
    func fullSharedBarStaysPut() {
        let bar = layout(.expanded, selection: MetricKind.allCases, alignment: .trailing)
        #expect(bar.items.first != .leadingSpacer)
        #expect(bar.items.last == .flexibleSpace)
    }

    @Test("A layout changes whenever the bar would have to be rebuilt")
    func equality() {
        #expect(layout(.expanded) == layout(.expanded))
        #expect(
            layout(.expanded, selection: [.cpu], alignment: .center)
                != layout(.expanded, selection: [.cpu], alignment: .trailing)
        )
        // A bar too full to move looks the same whatever the setting says.
        #expect(
            layout(.expanded, selection: MetricKind.allCases, alignment: .center)
                == layout(.expanded, selection: MetricKind.allCases, alignment: .trailing)
        )
        #expect(layout(.expanded, hasBattery: false) != layout(.expanded, hasBattery: true))
        #expect(layout(.fullscreen, supported: [.cpu]) != layout(.fullscreen))
        #expect(layout(.detail(.cpu)) != layout(.detail(.gpu)))
    }
}
