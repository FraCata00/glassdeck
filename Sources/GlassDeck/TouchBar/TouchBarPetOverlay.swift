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
    static let size = CGFloat(PetArt.canvasSize) * scale
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

    // MARK: - Crossing

    func cross(_ route: PetRoute, mood: PetMood) {
        self.mood = mood
        state = .crossing(route: route, start: CACurrentMediaTime())
        sprite.removeAllAnimations()
        sprite.isHidden = false
        face(leading: false)
        sprite.position = CGPoint(x: route.segments.last?.toX ?? 0, y: Self.baseline)
        setContents(.stand)

        let duration = route.duration
        guard duration > 0 else { return }
        let path = route.positionKeyframes
        sprite.add(keyframes("position.x", values: path.values, keyTimes: path.keyTimes, duration: duration), forKey: "cross")
        if let hops = route.hopKeyframes {
            let jump = keyframes("position.y", values: hops.values, keyTimes: hops.keyTimes, duration: duration)
            jump.isAdditive = true
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
        animateContents(frames, keyTimes: changes.map { $0.time / remaining }, duration: remaining, key: "poses")
    }

    /// Walks off past `endX` from wherever the pet is.
    func leave(to endX: CGFloat) {
        if case .hidden = state { return }
        state = .leaving
        sprite.removeAllAnimations()
        walk(to: endX, duration: Self.exitDuration, leading: false)
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
            setContents(.stand)
        case .blink:
            setContents(.stand)
            flash(.blink, for: PetRoute.blinkDuration)
        case .walk:
            let endX = home + behaviour.offset
            let distance = abs(endX - (sprite.presentation() ?? sprite).position.x)
            walk(to: endX, duration: distance / (mood.walkSpeed * Self.scale), leading: behaviour.facesLeading)
        case .hop:
            setContents(.stand)
            hop()
        case .turn:
            face(leading: behaviour.facesLeading)
            setContents(.stand)
        case .sleep:
            breath.toggle()
            setContents(breath ? .asleepBreath : .asleep)
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
            setContents(route.pose(at: min(elapsed, route.duration), stepInterval: mood.stepInterval))
            animatePoses(of: route, from: elapsed)
        case .leaving:
            // Off the bar, or about to be: nothing left to show.
            if sprite.animation(forKey: "cross") == nil { hide() }
        case .wandering, .hidden:
            break
        }
    }

    func hide() {
        // Called on every sample while there is no pet to show: nothing to
        // commit when it is already hidden.
        if case .hidden = state { return }
        sprite.removeAllAnimations()
        sprite.isHidden = true
        state = .hidden
    }

    // MARK: - Animation

    /// Walks from wherever the pet is to `endX`, facing the way it goes.
    private func walk(to endX: CGFloat, duration: TimeInterval, leading: Bool) {
        let startX = (sprite.presentation() ?? sprite).position.x
        sprite.removeAnimation(forKey: "cross")
        face(leading: leading)
        sprite.position = CGPoint(x: endX, y: Self.baseline)
        setContents(.stand)
        guard duration > 0 else { return }
        sprite.add(keyframes("position.x", values: [startX, endX], keyTimes: [0, 1], duration: duration), forKey: "cross")
        // The two walk frames for as long as the walk: a finite repeat, so the
        // animation ends with it and nothing keeps running after.
        guard let stand = image(.stand), let step = image(.step) else { return }
        let cycle = mood.stepInterval * 2
        let frames = animateContents([stand, step], keyTimes: [0, 0.5], duration: cycle, key: "poses")
        frames.repeatCount = Float((duration / cycle).rounded(.up))
    }

    private func hop(surprised: Bool = false) {
        let shape = PetRoute.hopShape
        let jump = keyframes(
            "position.y",
            values: shape.map(\.height),
            keyTimes: shape.map(\.time),
            duration: PetRoute.hopDuration
        )
        jump.isAdditive = true
        sprite.add(jump, forKey: "hop")
        flash(.jump, for: PetRoute.hopDuration, surprised: surprised)
    }

    /// Shows a pose for a moment over whatever the pet is doing, which
    /// carries on underneath when it ends.
    private func flash(_ pose: PetArt.Pose, for duration: TimeInterval, surprised: Bool = false) {
        guard let frame = image(pose, surprised: surprised) else { return }
        animateContents([frame], keyTimes: [0], duration: duration, key: "flash")
    }

    private func keyframes(_ keyPath: String, values: [Double], keyTimes: [Double], duration: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.duration = duration
        return animation
    }

    /// Steps the sprite through `frames`, each from its key time to the next.
    /// Returned so a caller can make it repeat; it is already added.
    @discardableResult
    private func animateContents(_ frames: [CGImage], keyTimes: [Double], duration: TimeInterval, key: String) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = duration
        sprite.add(animation, forKey: key)
        return animation
    }

    /// Sets the resting frame, skipping the transaction when it is already
    /// the one showing — most samples in a detail are a pet standing still.
    private func setContents(_ pose: PetArt.Pose) {
        guard let frame = image(pose) else { return }
        if let current = sprite.contents, (current as AnyObject) === frame { return }
        sprite.contents = frame
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
            setContents(.stand)
        }
        hop(surprised: true)
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { !sprite.isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { pet.title }
}
