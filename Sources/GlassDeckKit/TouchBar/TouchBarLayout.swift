import Foundation

/// How much of the Touch Bar GlassDeck is using.
public enum TouchBarMode: Hashable, Sendable {
    /// Nothing presented: the Touch Bar belongs to the system and the
    /// frontmost app again.
    case collapsed
    /// Just the compact meter, so GlassDeck never disappears entirely.
    case mini
    case expanded
    case fullscreen
    /// One metric expanded across the bar, reached by tapping its panel.
    case detail(MetricKind)

    /// Placement passed to the system: `0` keeps the Control Strip, `1` covers it.
    public var placement: Int {
        switch self {
        case .fullscreen, .detail: 1
        case .collapsed, .mini, .expanded: 0
        }
    }

    /// One step smaller. Shrinking stops at `mini` rather than at nothing.
    public var smaller: TouchBarMode {
        switch self {
        case .fullscreen, .detail: .expanded
        case .expanded, .mini, .collapsed: .mini
        }
    }

    /// One step larger.
    public var larger: TouchBarMode {
        switch self {
        case .collapsed, .mini: .expanded
        case .expanded, .fullscreen, .detail: .fullscreen
        }
    }

    public var expandedMetric: MetricKind? {
        if case let .detail(kind) = self { return kind }
        return nil
    }

    /// Whether this bar is worth redrawing at the sampling cadence.
    ///
    /// The Control Strip meter and the mini bar are a few points tall and
    /// carry no numbers: at the default cadence, redrawing them every 1.5 s
    /// spends the DFR round trip on a change nobody can see. They follow the
    /// coarse republication instead — the same one the menu bar glyph uses.
    /// The larger bars carry sparklines and readouts, where the cadence is
    /// the point, and keep it.
    public var wantsFineCadence: Bool {
        switch self {
        case .collapsed, .mini: false
        case .expanded, .fullscreen, .detail: true
        }
    }
}

/// Where the meters sit on the bar when they are not using its full width.
///
/// The raw value is the persisted setting, so it must stay stable.
public enum TouchBarAlignment: String, Sendable, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    public var id: String { rawValue }
}

/// What a presented bar holds and how wide each part of it is.
///
/// Worked out from plain values rather than from the live views, so the rules
/// that keep a bar inside the width the system grants can be tested without a
/// Touch Bar. Two layouts compare equal exactly when presenting one in place of
/// the other would change nothing, which is how the controller knows to rebuild.
public struct TouchBarLayout: Equatable, Sendable {
    public enum Item: Hashable, Sendable {
        /// Shifts the bar towards the Control Strip; `leadingSpacerWidth` wide.
        case leadingSpacer
        case flexibleSpace
        case metric(MetricKind)
        case battery
        case grow
        case dashboard
        case collapse
        case miniMeter
        case back
        case detail
    }

    /// Room a bar presented at placement 0 has beside the system Control Strip,
    /// measured on a 13-inch MacBook Pro with the system close box showing.
    ///
    /// The bar sizes itself to its content: ask for more and the trailing items
    /// are clipped, so panels are sized to fit this budget and alignment uses a
    /// spacer only as wide as the leftover space.
    public static let sharedRegionWidth: CGFloat = 540
    /// Usable width when GlassDeck owns the whole bar.
    public static let fullRegionWidth: CGFloat = 1004
    public static let itemSpacing: CGFloat = 8
    /// Pinned width of the shrink, grow and dashboard buttons.
    public static let controlWidth: CGFloat = 46
    /// Narrowest a metric panel gets before its graph stops being worth a glance.
    public static let minimumPanelWidth: CGFloat = 84
    /// Sharing the bar with the Control Strip leaves roughly 540 pt: four
    /// narrow panels plus the controls is the most that stays legible.
    public static let maximumSharedPanels = 4
    /// The two buttons that ride along in full width: the dashboard and the
    /// chevron. The grow button is not among them — there is nothing larger
    /// than full width — so its width goes to the panels.
    static let fullscreenControlCount = 2

    public let mode: TouchBarMode
    public let items: [Item]
    /// Width of every metric panel on this bar.
    public let panelWidth: CGFloat
    /// Width of the `.leadingSpacer` item, or `0` when there is none.
    public let leadingSpacerWidth: CGFloat

    /// - Parameters:
    ///   - selection: The metrics chosen for the Touch Bar.
    ///   - order: The user's metric order, holding every kind.
    ///   - supported: The metrics this machine can report.
    ///   - batteryWidth: Width of the battery chip.
    ///   - miniMeterWidth: Width of the compact meter on the mini bar.
    public init(
        mode: TouchBarMode,
        selection: [MetricKind],
        order: [MetricKind],
        supported: Set<MetricKind>,
        hasBattery: Bool,
        alignment: TouchBarAlignment,
        batteryWidth: CGFloat,
        miniMeterWidth: CGFloat
    ) {
        self.mode = mode

        let fixedItems = (hasBattery ? 1 : 0) + Self.fullscreenControlCount
        let fixedWidth = (hasBattery ? batteryWidth : 0) + CGFloat(Self.fullscreenControlCount) * Self.controlWidth
        let metrics = Self.metrics(
            for: mode,
            selection: selection,
            order: order,
            supported: supported,
            fixedItems: fixedItems,
            fixedWidth: fixedWidth
        )
        let panelWidth = mode == .fullscreen
            ? Self.fullscreenPanelWidth(count: metrics.count, fixedItems: fixedItems, fixedWidth: fixedWidth)
            : Self.minimumPanelWidth
        self.panelWidth = panelWidth

        // The system draws its own close box on the left while GlassDeck is
        // frontmost, so GlassDeck's own controls all live on the right. Items are
        // dropped rather than squeezed — the Dashboard button only earns its
        // place in full width, where the menu bar panel is not the closer
        // alternative.
        let content: [Item]
        switch mode {
        case .collapsed:
            content = []
        case .detail:
            content = [.back, .detail, .collapse]
        case .mini:
            content = [.miniMeter, .grow, .collapse]
        case .expanded, .fullscreen:
            // The grow button is only drawn where there is something larger to
            // grow into. In full width it used to sit there showing a shrink glyph
            // and calling `grow()`, which returns full width again: a dead
            // control, beside the chevron that does the shrinking for real.
            content = metrics.map(Item.metric)
                + (hasBattery ? [.battery] : [])
                + (mode.larger != mode ? [.grow] : [])
                + (mode == .fullscreen ? [.dashboard] : [])
                + [.collapse]
        }

        // Full width has nowhere to move to, and neither has a bar with nothing
        // on it; the other sizes honour the alignment setting.
        switch mode {
        case .collapsed, .fullscreen, .detail:
            items = content
            leadingSpacerWidth = 0
        case .mini, .expanded:
            let width = content.reduce(CGFloat(0)) { total, item in
                switch item {
                case .miniMeter: total + miniMeterWidth
                case .battery: total + batteryWidth
                case .grow, .collapse, .dashboard: total + Self.controlWidth
                default: total + panelWidth
                }
            } + CGFloat(content.count - 1) * Self.itemSpacing
            let slack = Self.sharedRegionWidth - width

            if slack > 24, alignment != .leading {
                items = [.leadingSpacer] + content
                // The spacer is an item too, so the system puts a gap after it:
                // left out, it pushed the bar 8 pt past the region and left a
                // centred bar 8 pt nearer the Control Strip than the close box.
                let shift = alignment == .center ? slack / 2 : slack
                leadingSpacerWidth = shift - Self.itemSpacing
            } else {
                // A full bar cannot be moved; forcing it would push items under
                // the Control Strip, where the system clips them.
                items = content + [.flexibleSpace]
                leadingSpacerWidth = 0
            }
        }
    }

    /// The metric panels on the bar, in order.
    public var metrics: [MetricKind] {
        items.compactMap { if case let .metric(kind) = $0 { kind } else { nil } }
    }

    /// Fan speeds are deliberately fullscreen-only: the shorter bar has no room
    /// for a fifth panel without squeezing the graphs into illegibility. Battery
    /// is never a panel — it rides along as the compact chip on the right, and
    /// power rides along with it.
    private static func metrics(
        for mode: TouchBarMode,
        selection: [MetricKind],
        order: [MetricKind],
        supported: Set<MetricKind>,
        fixedItems: Int,
        fixedWidth: CGFloat
    ) -> [MetricKind] {
        switch mode {
        case .collapsed, .mini, .detail:
            return []
        case .expanded:
            let chosen = selection.filter { ![.battery, .power, .fans, .temperature].contains($0) }
            return Array(chosen.prefix(maximumSharedPanels))
        case .fullscreen:
            // Hardware readings that only full width has room for join whatever
            // was chosen, then everything goes back into the user's order: the
            // extras are appended, not ranked.
            let chosen = Set(selection).subtracting([.battery, .power]).union([.fans, .temperature])
            let metrics = order.filter { chosen.contains($0) && supported.contains($0) }
            let maximum = maximumFullscreenPanels(fixedItems: fixedItems, fixedWidth: fixedWidth)
            return Array(metrics.prefix(maximum))
        }
    }

    /// Width of one panel in full width.
    ///
    /// The panels are stretched to use the whole bar, so enabling or disabling a
    /// metric widens or narrows the rest rather than changing how much of the bar
    /// sits empty — five metrics used to leave a fifth of it black. The shared
    /// bar keeps a fixed width on purpose: there the leftover space is exactly
    /// what the alignment setting slides the bar around in.
    private static func fullscreenPanelWidth(count: Int, fixedItems: Int, fixedWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return minimumPanelWidth }
        let items = count + fixedItems
        let free = fullRegionWidth - fixedWidth - itemSpacing * CGFloat(items - 1)
        // Rounded down, not just divided: a fractional width is rounded up again
        // when the panel is laid out, and seven of those pushed the last button
        // off the end of the bar.
        return max(minimumPanelWidth, (free / CGFloat(count)).rounded(.down))
    }

    /// The most panels full width can hold before they stop being legible.
    /// Panels shrink to make room, so this is a floor on the width rather than a
    /// count worked out from a fixed one.
    private static func maximumFullscreenPanels(fixedItems: Int, fixedWidth: CGFloat) -> Int {
        var count = 1
        while count < MetricKind.allCases.count,
              fullscreenPanelWidth(count: count + 1, fixedItems: fixedItems, fixedWidth: fixedWidth) > minimumPanelWidth {
            count += 1
        }
        return count
    }
}
