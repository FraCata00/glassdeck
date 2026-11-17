import AppKit
import GlassDeckKit
import QuartzCore

/// The pet, laid over the Touch Bar's items.
///
/// The bar is a row of separate items with no view spanning it, so this view is
/// added on top of them in the window that hosts them and covers it whole. It
/// draws nothing itself: the pet is one layer whose contents are swapped
/// between prerendered frames, and a crossing is a single finite Core
/// Animation run by the render server. Nothing underneath is invalidated when
/// the pet moves, and no timer runs in this process while it walks — the
/// metric panels' `draw(_:)` is where the bar's cost lives, and the pet must
/// never add to it.
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

    private enum State: Equatable {
        case hidden
        /// Walking across; the crossing began at `start` (media time).
        case crossing(start: CFTimeInterval, duration: TimeInterval)
        case lingering
        case resting
        case leaving
    }

    private let sprite = CALayer()
    private var state: State = .hidden
    private var mood: PetMood = .calm
    private var restingFrame = 0

    /// The pet stands on the bar's lower edge, a point up so its feet are not
    /// clipped by the bar's rounded corners.
    private static let baseline: CGFloat = 1
    private static let size = CGFloat(PetArt.canvasSize)
    /// How long walking off the far edge takes.
    private static let exitDuration: TimeInterval = 2.5

    private struct ImageKey: Hashable {
        var mood: PetMood
        var pose: PetArt.Pose
        var surprised: Bool
    }

    /// Rasterised once per mood and pose: a dozen 20-pixel images at most.
    private var images: [ImageKey: [CGImage]] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        sprite.anchorPoint = .zero
        sprite.bounds = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        // Nearest-neighbour keeps every art pixel a crisp 2 × 2 block on the
        // bar's 2× panel instead of a blur.
        sprite.magnificationFilter = .nearest
        sprite.isHidden = true
        // Every change here is either instant or an explicit animation; the
        // layer's implicit quarter-second fades would smear the pixel art.
        sprite.actions = ["position": NSNull(), "contents": NSNull(), "hidden": NSNull(), "bounds": NSNull()]
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

    // MARK: - What the pet does

    /// Sets off from `startX` to `endX`, in this view's coordinates.
    func cross(from startX: CGFloat, to endX: CGFloat, duration: TimeInterval, mood: PetMood) {
        self.mood = mood
        state = .crossing(start: CACurrentMediaTime(), duration: duration)
        sprite.removeAllAnimations()
        sprite.isHidden = false
        sprite.position = CGPoint(x: endX, y: Self.baseline)

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = startX
        move.toValue = endX
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        sprite.add(move, forKey: "cross")
        walk(for: duration)
    }

    /// Stops where the crossing ended and walks in place, one frame a sample.
    func linger(mood: PetMood) {
        self.mood = mood
        state = .lingering
        sprite.removeAnimation(forKey: "walk")
        advanceRestingFrame()
    }

    /// Walks off past `endX`.
    func leave(to endX: CGFloat) {
        guard state != .hidden else { return }
        let startX = (sprite.presentation() ?? sprite).position.x
        state = .leaving
        sprite.removeAllAnimations()
        sprite.position = CGPoint(x: endX, y: Self.baseline)

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = startX
        move.toValue = endX
        move.duration = Self.exitDuration
        sprite.add(move, forKey: "cross")
        walk(for: Self.exitDuration)
    }

    /// Sits at `origin` — in a metric's detail — acting out `mood`.
    func rest(at origin: CGPoint, mood: PetMood) {
        if state != .resting || sprite.position != origin {
            sprite.removeAllAnimations()
            sprite.position = origin
            sprite.isHidden = false
            state = .resting
        }
        self.mood = mood
        advanceRestingFrame()
    }

    /// Called on every sample while the pet is about: keeps its frames in step
    /// with the mood and, standing still, moves it on by one frame.
    func show(mood: PetMood) {
        let changed = mood != self.mood
        self.mood = mood
        switch state {
        case let .crossing(start, duration):
            guard changed else { return }
            let remaining = start + duration - CACurrentMediaTime()
            if remaining > 0 { walk(for: remaining) } else { sprite.contents = frames(.moving).first }
        case .lingering, .resting:
            advanceRestingFrame()
        case .leaving:
            // Off the bar, or about to be: nothing left to show.
            if sprite.animation(forKey: "cross") == nil { hide() }
        case .hidden:
            break
        }
    }

    func hide() {
        sprite.removeAllAnimations()
        sprite.isHidden = true
        state = .hidden
    }

    /// Where a crossing starts and ends: just off the leading edge, and past
    /// the trailing one.
    var offscreenLeading: CGFloat { -Self.size }
    var offscreenTrailing: CGFloat { bounds.width + Self.size }
    static var spriteWidth: CGFloat { size }

    // MARK: - Animation

    /// Cycles the walk frames for `duration` seconds: a finite repeat, so the
    /// animation ends with the crossing and nothing keeps running after it.
    private func walk(for duration: TimeInterval) {
        let frames = frames(.moving)
        sprite.contents = frames.first
        guard frames.count > 1, duration > 0 else { return }
        let cycle = mood.stepInterval * Double(frames.count)
        let walk = CAKeyframeAnimation(keyPath: "contents")
        walk.values = frames
        walk.calculationMode = .discrete
        walk.duration = cycle
        walk.repeatCount = Float((duration / cycle).rounded(.up))
        sprite.add(walk, forKey: "walk")
    }

    private func advanceRestingFrame() {
        let frames = frames(state == .lingering ? .moving : .resting)
        guard !frames.isEmpty else { return }
        restingFrame = (restingFrame + 1) % frames.count
        sprite.contents = frames[restingFrame]
    }

    private func frames(_ pose: PetArt.Pose, surprised: Bool = false) -> [CGImage] {
        let key = ImageKey(mood: mood, pose: pose, surprised: surprised)
        if let cached = images[key] { return cached }
        let rendered = PetArt.frames(for: pet, mood: mood, pose: pose, surprised: surprised).compactMap(Self.image)
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
        hop()
    }

    override func mouseDown(with event: NSEvent) {
        hop()
    }

    /// A tap makes the pet jump and pull a face. Both are one-shot animations
    /// laid over whatever it is doing, which carries on underneath.
    private func hop() {
        let jump = CAKeyframeAnimation(keyPath: "position.y")
        jump.values = [0, 6, 0]
        jump.keyTimes = [0, 0.4, 1]
        jump.isAdditive = true
        jump.duration = 0.35
        sprite.add(jump, forKey: "hop")

        guard let face = frames(state == .resting ? .resting : .moving, surprised: true).first else { return }
        let surprise = CAKeyframeAnimation(keyPath: "contents")
        surprise.values = [face]
        surprise.calculationMode = .discrete
        surprise.duration = 0.8
        sprite.add(surprise, forKey: "surprise")
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { !sprite.isHidden }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { pet.title }
}
