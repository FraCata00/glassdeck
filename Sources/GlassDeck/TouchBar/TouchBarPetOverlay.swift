import AppKit
import GlassDeckKit
import QuartzCore

/// The pet, laid over the Touch Bar's items.
///
/// The bar is a row of separate items with no view spanning it, so this view is
/// added on top of them in the window that hosts them and covers it whole. It
/// draws nothing itself: the pet is one layer whose contents are swapped
/// between prerendered frames, and everything it does is a finite Core
/// Animation run by the render server — a whole crossing, stops and hops
/// included, is one. Nothing underneath is invalidated when the pet moves, and
/// no timer runs in this process: the panels' `draw(_:)` is where the bar's
/// cost lives, and the pet must never add to it. When it is not crossing, the
/// next little thing it does is chosen on the next sample, which is the only
/// clock it has.
///
/// Touches pass straight through everywhere except on the pet itself.
final class TouchBarPetOverlay: NSView {
    var pet: TouchBarPet = .off {
        didSet {
            guard pet != oldValue else { return }
            images.removeAll()
            hide()
        }
    }

    private enum State {
        case hidden
        /// Following `route`, which began at `start` (media time).
        case crossing(route: PetRoute, start: CFTimeInterval)
        /// Pottering about `home`, a centre x in this view.
        case wandering(home: CGFloat, behaviour: PetBehaviour)
        case leaving
    }

    private let sprite = CALayer()
    private var state: State = .hidden
    private var mood: PetMood = .calm
    private var random = SystemRandomNumberGenerator()
    private var breath = false

    /// Points per art pixel. One and a half makes every pixel an exact 3 × 3
    /// block on the bar's 2× panel — a fractional size such as 1.25 would
    /// draw uneven rows — and puts the 20-pixel canvas at the bar's full
    /// 30 pt, the body about 21 pt of it and the props in the band above.
    private static let scale: CGFloat = 1.5
    private static let size = CGFloat(PetArt.canvasSize) * scale
    /// The canvas fills the bar's height, so it stands right on the edge; its
    /// lowest rows are feet, well clear of the bar's rounded ends.
    private static let baseline: CGFloat = 0
    /// How long walking off the far edge takes.
    private static let exitDuration: TimeInterval = 2.5

    private struct ImageKey: Hashable {
        var mood: PetMood
        var pose: PetArt.Pose
        var surprised: Bool
    }

    /// Rasterised on first use: a handful of 20-pixel images per mood.
    private var images: [ImageKey: CGImage] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Anchored at the feet, in the middle, so turning round is a flip on
        // the spot rather than a jump sideways.
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        // Nearest-neighbour keeps every art pixel a crisp block instead of a
        // blur.
        sprite.magnificationFilter = .nearest
        sprite.isHidden = true
        // Every change here is either instant or an explicit animation; the
        // layer's implicit quarter-second fades would smear the pixel art.
        sprite.actions = [
            "position": NSNull(), "contents": NSNull(), "hidden": NSNull(),
            "bounds": NSNull(), "transform": NSNull(),
        ]
        layer?.addSublayer(sprite)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Hosting

    /// Puts the overlay on top of everything in `host`, covering it.
    func attach(to host: NSView) {
        if superview !== host {
            removeFromSuperview()
            frame = host.bounds
            autoresizingMask = [.width, .height]
            host.addSubview(self)
        } else if host.subviews.last !== self {
            host.addSubview(self, positioned: .above, relativeTo: nil)
        }
    }

    func detach() {
        hide()
        removeFromSuperview()
    }

    /// Centre x positions just off either edge.
    var offscreenLeading: CGFloat { -Self.size / 2 }
    var offscreenTrailing: CGFloat { bounds.width + Self.size / 2 }
    static var spriteWidth: CGFloat { size }

    // MARK: - Crossing

    func cross(_ route: PetRoute, mood: PetMood) {
        self.mood = mood
        state = .crossing(route: route, start: CACurrentMediaTime())
        sprite.removeAllAnimations()
        sprite.isHidden = false
        face(leading: false)
        sprite.position = CGPoint(x: route.segments.last?.toX ?? 0, y: Self.baseline)
        sprite.contents = image(.stand)

        let duration = route.duration
        guard duration > 0 else { return }
        var xs: [Double] = [route.segments.first?.fromX ?? 0]
        var xTimes: [Double] = [0]
        var hopTimes: [Double] = [0]
        var hops: [Double] = [0]
        for segment in route.segments {
            xs.append(segment.toX)
            xTimes.append(segment.end / duration)
            if segment.move == .hop {
                hopTimes += [segment.start, (segment.start + segment.end) / 2, segment.end].map { $0 / duration }
                hops += [0, PetRoute.hopHeight, 0]
            }
        }
        hopTimes.append(1)
        hops.append(0)

        let move = CAKeyframeAnimation(keyPath: "position.x")
        move.values = xs
        move.keyTimes = xTimes.map { NSNumber(value: $0) }
        move.duration = duration
        sprite.add(move, forKey: "cross")

        if hops.count > 2 {
            let jump = CAKeyframeAnimation(keyPath: "position.y")
            jump.values = hops
            jump.keyTimes = hopTimes.map { NSNumber(value: $0) }
            jump.isAdditive = true
            jump.duration = duration
            sprite.add(jump, forKey: "hops")
        }
        animatePoses(of: route, from: 0)
    }

    /// The frames of a crossing as one discrete keyframe animation from
    /// `elapsed` to the end. Replaced, from where the pet is, when the mood
    /// changes on the way.
    private func animatePoses(of route: PetRoute, from elapsed: TimeInterval) {
        let remaining = route.duration - elapsed
        guard remaining > 0 else { return }
        let changes = route.poseChanges(from: elapsed, stepInterval: mood.stepInterval)
        let frames = changes.compactMap { image($0.pose) }
        guard frames.count == changes.count, !frames.isEmpty else { return }
        let poses = CAKeyframeAnimation(keyPath: "contents")
        poses.values = frames
        poses.keyTimes = changes.map { NSNumber(value: $0.time / remaining) }
        poses.calculationMode = .discrete
        poses.duration = remaining
        sprite.add(poses, forKey: "poses")
    }

    /// Walks off past `endX` from wherever the pet is.
    func leave(to endX: CGFloat) {
        if case .hidden = state { return }
        let startX = (sprite.presentation() ?? sprite).position.x
        state = .leaving
        sprite.removeAllAnimations()
        face(leading: false)
        sprite.position = CGPoint(x: endX, y: Self.baseline)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = startX
        move.toValue = endX
        move.duration = Self.exitDuration
        sprite.add(move, forKey: "cross")
        walkCycle(for: Self.exitDuration)
    }

    // MARK: - Pottering about

    /// Called once a sample while the pet stays around `home` — in a metric's
    /// detail, or at the end of the bar while a spike lasts — and does the next
    /// little thing: stand, blink, a few steps, a hop, turn round, or doze.
    func wander(home: CGFloat, range: ClosedRange<Double>, mood: PetMood) {
        self.mood = mood
        var behaviour: PetBehaviour
        if case let .wandering(currentHome, current) = state, currentHome == home, current.range == range {
            behaviour = current
        } else {
            // Arriving: from wherever the crossing left it, or straight onto
            // the spot when it appears in a detail.
            behaviour = PetBehaviour(range: range)
            sprite.removeAllAnimations()
            sprite.isHidden = false
            sprite.position = CGPoint(x: home, y: Self.baseline)
            face(leading: false)
        }
        let activity = behaviour.next(mood: mood, random: &random)
        state = .wandering(home: home, behaviour: behaviour)
        perform(activity, home: home, behaviour: behaviour)
    }

    private func perform(_ activity: PetBehaviour.Activity, home: CGFloat, behaviour: PetBehaviour) {
        switch activity {
        case .stand:
            sprite.contents = image(.stand)
        case .blink:
            sprite.contents = image(.stand)
            flash(.blink, for: 0.18)
        case .walk:
            let startX = (sprite.presentation() ?? sprite).position.x
            let endX = home + behaviour.offset
            // About three art pixels a step: the walk cycle sets the pace.
            let duration = abs(endX - startX) / (3 * Self.scale / mood.stepInterval)
            sprite.removeAnimation(forKey: "cross")
            face(leading: behaviour.facesLeading)
            sprite.position = CGPoint(x: endX, y: Self.baseline)
            sprite.contents = image(.stand)
            guard duration > 0 else { return }
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = startX
            move.toValue = endX
            move.duration = duration
            sprite.add(move, forKey: "cross")
            walkCycle(for: duration)
        case .hop:
            sprite.contents = image(.stand)
            hop()
        case .turn:
            face(leading: behaviour.facesLeading)
            sprite.contents = image(.stand)
        case .sleep:
            breath.toggle()
            sprite.contents = image(breath ? .asleepBreath : .asleep)
        }
    }

    // MARK: - While it is about

    /// Called on every sample while the pet is crossing or leaving: keeps the
    /// frames in step with the mood.
    func show(mood: PetMood) {
        let changed = mood != self.mood
        self.mood = mood
        switch state {
        case let .crossing(route, start):
            guard changed else { return }
            sprite.removeAnimation(forKey: "poses")
            let elapsed = CACurrentMediaTime() - start
            sprite.contents = image(route.pose(at: min(elapsed, route.duration), stepInterval: mood.stepInterval))
            animatePoses(of: route, from: elapsed)
        case .leaving:
            // Off the bar, or about to be: nothing left to show.
            if sprite.animation(forKey: "cross") == nil { hide() }
        case .wandering, .hidden:
            break
        }
    }

    func hide() {
        sprite.removeAllAnimations()
        sprite.isHidden = true
        state = .hidden
    }

    // MARK: - Animation

    /// Cycles the two walk frames for `duration` seconds: a finite repeat, so
    /// the animation ends with the walk and nothing keeps running after it.
    private func walkCycle(for duration: TimeInterval) {
        guard let stand = image(.stand), let step = image(.step), duration > 0 else { return }
        let cycle = mood.stepInterval * 2
        let walk = CAKeyframeAnimation(keyPath: "contents")
        walk.values = [stand, step]
        walk.calculationMode = .discrete
        walk.duration = cycle
        walk.repeatCount = Float((duration / cycle).rounded(.up))
        sprite.add(walk, forKey: "poses")
    }

    private func hop(surprised: Bool = false) {
        let jump = CAKeyframeAnimation(keyPath: "position.y")
        jump.values = [0, PetRoute.hopHeight, 0]
        jump.keyTimes = [0, 0.45, 1]
        jump.isAdditive = true
        jump.duration = PetRoute.hopDuration
        sprite.add(jump, forKey: "hop")
        flash(.jump, for: PetRoute.hopDuration, surprised: surprised)
    }

    /// Shows a pose for a moment over whatever the pet is doing, which
    /// carries on underneath when it ends.
    private func flash(_ pose: PetArt.Pose, for duration: TimeInterval, surprised: Bool = false) {
        guard let frame = image(pose, surprised: surprised) else { return }
        let flash = CAKeyframeAnimation(keyPath: "contents")
        flash.values = [frame]
        flash.calculationMode = .discrete
        flash.duration = duration
        sprite.add(flash, forKey: "flash")
    }

    /// The art faces the trailing edge; facing the other way is a mirror.
    private func face(leading: Bool) {
        sprite.transform = leading ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    private func image(_ pose: PetArt.Pose, surprised: Bool = false) -> CGImage? {
        let key = ImageKey(mood: mood, pose: pose, surprised: surprised)
        if let cached = images[key] { return cached }
        guard let bitmap = PetArt.frame(for: pet, mood: mood, pose: pose, surprised: surprised),
              let rendered = Self.image(from: bitmap)
        else { return nil }
        images[key] = rendered
        return rendered
    }

    private static func image(from bitmap: PetBitmap) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bitmap.rgba) as CFData) else { return nil }
        // Every pixel is opaque or clear, so the straight bytes are also the
        // premultiplied ones Core Animation wants.
        return CGImage(
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bitmap.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Touch

    /// Only the pet takes touches; everywhere else the bar underneath gets them.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !sprite.isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        let frame = (sprite.presentation() ?? sprite).frame.insetBy(dx: -4, dy: -4)
        return frame.contains(local) ? self : nil
    }

    override func touchesBegan(with event: NSEvent) {
        greet()
    }

    override func mouseDown(with event: NSEvent) {
        greet()
    }

    /// A tap wakes the pet if it was asleep and makes it jump, surprised.
    private func greet() {
        if case .wandering(let home, var behaviour) = state, behaviour.isAsleep {
            behaviour.wake()
            state = .wandering(home: home, behaviour: behaviour)
            sprite.contents = image(.stand)
        }
        hop(surprised: true)
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { !sprite.isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { pet.title }
}
