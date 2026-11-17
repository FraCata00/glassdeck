import Foundation

/// One frame of a pet, as straight RGBA bytes, top row first. Every pixel is
/// either opaque or fully transparent, so premultiplied and straight alpha are
/// the same bytes and the app can hand them to Core Graphics as they are.
public struct PetBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public func alpha(x: Int, y: Int) -> UInt8 { rgba[(y * width + x) * 4 + 3] }
    public var opaquePixelCount: Int { stride(from: 3, to: rgba.count, by: 4).count { rgba[$0] != 0 } }
}

/// The pets' pixel art and how a mood is dressed onto it.
///
/// Each animal has three poses drawn by hand — two walking frames and one
/// asleep — on a 16 × 14 grid, placed low on a 20 × 20 canvas so the props a
/// mood adds (a sweat drop, a spark, a parcel) have room above and beside it.
/// The moods are props and recolourings rather than separate drawings: three
/// animals times eight moods would be fifty drawings to keep consistent, and
/// at this size a prop reads as clearly as a new pose.
///
/// On the bar one pixel here is one point, so a pet is 20 pt square — two
/// thirds of the bar's height, small enough not to hide a reading for long.
public enum PetArt {
    public static let canvasSize = 20
    static let bodyWidth = 16
    static let bodyHeight = 14
    static let bodyOrigin = (x: 2, y: 6)

    public enum Pose: Sendable, Hashable {
        /// Crossing the bar, or walking in place while it waits at the far end.
        case moving
        /// Sitting still: in a metric's detail, or asleep.
        case resting
    }

    /// The frames for a pet in a mood, in the order they cycle. Empty for `off`.
    public static func frames(
        for pet: TouchBarPet,
        mood: PetMood,
        pose: Pose,
        surprised: Bool = false
    ) -> [PetBitmap] {
        guard let sheet = sheet(for: pet) else { return [] }
        let palette = recoloured(sheet.palette, for: mood)

        let bodies: [[String]] = if mood == .sleepy, pose == .resting {
            [sheet.asleep, sheet.asleep]
        } else {
            [sheet.walkA, sheet.walkB]
        }

        return bodies.enumerated().map { index, body in
            var canvas = Canvas()
            canvas.stamp(body, at: bodyOrigin, palette: palette)
            for prop in props(for: pet, mood: mood, frame: index, surprised: surprised) {
                canvas.stamp(prop.grid, at: prop.origin, palette: Self.propPalette)
            }
            return canvas.bitmap
        }
    }

    // MARK: - Sheets

    struct Sheet {
        var walkA: [String]
        var walkB: [String]
        var asleep: [String]
        /// Index → 0xRRGGBB. `1` outline, `2` body, `3` highlight, `4` eyes and
        /// nose, `5` eye shine, `6` accent (mouth, ears).
        var palette: [Character: UInt32]
    }

    static func sheet(for pet: TouchBarPet) -> Sheet? {
        switch pet {
        case .off: nil
        case .octopus: octopus
        case .frog: frog
        case .coco: coco
        }
    }

    static let octopus = Sheet(
        walkA: [
            ".....111111.....",
            "...1122222211...",
            "..122222222221..",
            "..123322222221..",
            ".12332222222221.",
            ".12222222222221.",
            ".12254222254221.",
            ".12244222244221.",
            ".12222266222221.",
            "..122222222221..",
            "..12.12..21.21..",
            ".12..12..21..21.",
            ".1...12..21...1.",
            "......1..1......",
        ],
        walkB: [
            ".....111111.....",
            "...1122222211...",
            "..122222222221..",
            "..123322222221..",
            ".12332222222221.",
            ".12222222222221.",
            ".12254222254221.",
            ".12244222244221.",
            ".12222266222221.",
            "..122222222221..",
            "..21.21..12.12..",
            "..21..21.12..12.",
            "...1...1.1...1..",
            "................",
        ],
        asleep: [
            "................",
            "................",
            ".....111111.....",
            "...1122222211...",
            "..122222222221..",
            "..123322222221..",
            ".12332222222221.",
            ".12222222222221.",
            ".12112222221121.",
            ".12222266222221.",
            "..122222222221..",
            "..121212121212..",
            "...1.1.1.1.1.1..",
            "................",
        ],
        palette: ["1": 0x5B2A6E, "2": 0xE07BB5, "3": 0xF7C1DE, "4": 0x1A1020, "5": 0xFFFFFF, "6": 0x9C3D73]
    )

    /// Hops rather than walks: crouched, then in the air.
    static let frog = Sheet(
        walkA: [
            "................",
            "................",
            "................",
            "................",
            "...111....111...",
            "..15541..15541..",
            "..122222222221..",
            ".12222222222221.",
            ".12666666666621.",
            ".12333333333321.",
            ".12233333333221.",
            "1222122222212221",
            "1221.111111.1221",
            ".11..........11.",
        ],
        walkB: [
            "................",
            "...111....111...",
            "..15541..15541..",
            "..122222222221..",
            ".12222222222221.",
            ".12666666666621.",
            ".12333333333321.",
            ".12233333333221.",
            "..122222222221..",
            "..12.1....1.21..",
            ".12..1....1..21.",
            ".1............1.",
            "................",
            "................",
        ],
        asleep: [
            "................",
            "................",
            "................",
            "................",
            "...111....111...",
            "..11111..11111..",
            "..122222222221..",
            ".12222222222221.",
            ".12666666666621.",
            ".12333333333321.",
            ".12233333333221.",
            "1222122222212221",
            "1221.111111.1221",
            ".11..........11.",
        ],
        palette: ["1": 0x1F4D1A, "2": 0x5CB338, "3": 0xC9E89A, "4": 0x101010, "5": 0xFFFFFF, "6": 0x2E6B22]
    )

    /// A red toy poodle in a teddy-bear cut, facing the way it walks: a round
    /// curly head, long ears close to the face, a black button nose and a pom
    /// of a tail. The broken outline is what says "curls" at this size.
    static let coco = Sheet(
        walkA: [
            "..........1111..",
            ".........132331.",
            "........13232321",
            "..11....12322421",
            ".1331...16622224",
            ".1321...16632221",
            "...1111111661211",
            "..1323232326611.",
            ".13232323232321.",
            ".12323232323221.",
            "..122222222221..",
            "..121......121..",
            "..121......121..",
            "..11.......11...",
        ],
        walkB: [
            "..........1111..",
            ".........132331.",
            "........13232321",
            "..11....12322421",
            ".1331...16622224",
            ".1321...16632221",
            "...1111111661211",
            "..1323232326611.",
            ".13232323232321.",
            ".12323232323221.",
            "..122222222221..",
            "...121....121...",
            "....121..121....",
            ".....11..11.....",
        ],
        asleep: [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            ".....111111.....",
            "...1132323211...",
            "..132323232321..",
            ".13232366232321.",
            ".12323661142321.",
            ".12222222222221.",
            "..111111111111..",
            "................",
        ],
        // Russet, from the photo: the coat stays this colour whatever the bar's
        // style, because it is what makes it Coco.
        palette: ["1": 0x5A2A12, "2": 0xB5562A, "3": 0xD9844F, "4": 0x140C08, "5": 0xFFFFFF, "6": 0x8A3B1A]
    )

    // MARK: - Moods

    /// Hot pets flush and a drained one fades; the outline and the eyes are
    /// left alone so the animal stays recognisable.
    static func recoloured(_ palette: [Character: UInt32], for mood: PetMood) -> [Character: UInt32] {
        switch mood {
        case .hot:
            palette.merging([
                "2": blend(palette["2"] ?? 0, 0xFF4A3A, 0.4),
                "3": blend(palette["3"] ?? 0, 0xFF8A70, 0.4),
            ]) { $1 }
        case .drained:
            palette.mapValues { muted($0) }.merging(["4": palette["4"] ?? 0, "5": palette["5"] ?? 0]) { $1 }
        case .squeezed, .busy, .carrying, .charging, .sleepy, .calm:
            palette
        }
    }

    struct Prop {
        var grid: [String]
        var origin: (x: Int, y: Int)
    }

    static let propPalette: [Character: UInt32] = [
        "a": 0x7EC8F0, // sweat
        "y": 0xFFD23F, // spark
        "w": 0xFFFFFF, // sleep, surprise, speed lines
        "b": 0xC79A5B, // parcel
        "t": 0x8A6438, // parcel tape
        "r": 0xFF6B5B, // pressure marks
        "p": 0xE8708A, // tongue
    ]

    static func props(for pet: TouchBarPet, mood: PetMood, frame: Int, surprised: Bool) -> [Prop] {
        var props: [Prop] = []
        switch mood {
        case .hot:
            props.append(Prop(grid: [".a.", "aaa", "aaa", ".a."], origin: (x: 15, y: frame == 0 ? 2 : 3)))
        case .charging:
            props.append(Prop(grid: ["..y", ".y.", "yyy", ".y.", "y.."], origin: (x: 9, y: 0)))
        case .sleepy:
            // The z drifts up a pixel between frames, which is all the
            // breathing a sleeping pet needs.
            props.append(Prop(grid: ["www", "..w", ".w.", "www"], origin: (x: 15, y: frame == 0 ? 2 : 1)))
        case .carrying:
            props.append(Prop(grid: ["btbb", "tttt", "btbb", "btbb"], origin: (x: 3, y: 2)))
        case .busy:
            props.append(Prop(grid: ["ww.", "...", ".ww", "...", "ww."], origin: (x: 0, y: frame == 0 ? 10 : 11)))
        case .squeezed:
            props.append(Prop(grid: ["r.", ".r", ".r", "r."], origin: (x: 0, y: 10)))
            props.append(Prop(grid: [".r", "r.", "r.", ".r"], origin: (x: 18, y: 10)))
        case .drained, .calm:
            break
        }
        // Coco pants when working hard or hot: a tongue under the nose.
        if pet == .coco, mood == .busy || mood == .hot {
            props.append(Prop(grid: ["p", "p"], origin: (x: 16, y: 12)))
        }
        if surprised {
            props.append(Prop(grid: ["w", "w", ".", "w"], origin: (x: 10, y: 0)))
        }
        return props
    }

    // MARK: - Pixels

    struct Canvas {
        var rgba = [UInt8](repeating: 0, count: PetArt.canvasSize * PetArt.canvasSize * 4)

        /// Paints a grid's coloured cells; `.` and anything off the canvas or
        /// missing from the palette is left as it was.
        mutating func stamp(_ grid: [String], at origin: (x: Int, y: Int), palette: [Character: UInt32]) {
            for (row, line) in grid.enumerated() {
                for (column, cell) in line.enumerated() {
                    guard let colour = palette[cell] else { continue }
                    let x = origin.x + column, y = origin.y + row
                    guard (0..<PetArt.canvasSize).contains(x), (0..<PetArt.canvasSize).contains(y) else { continue }
                    let offset = (y * PetArt.canvasSize + x) * 4
                    rgba[offset] = UInt8((colour >> 16) & 0xFF)
                    rgba[offset + 1] = UInt8((colour >> 8) & 0xFF)
                    rgba[offset + 2] = UInt8(colour & 0xFF)
                    rgba[offset + 3] = 0xFF
                }
            }
        }

        var bitmap: PetBitmap { PetBitmap(width: PetArt.canvasSize, height: PetArt.canvasSize, rgba: rgba) }
    }

    static func blend(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// Halfway to its own grey, and a little darker.
    static func muted(_ colour: UInt32) -> UInt32 {
        let r = Double((colour >> 16) & 0xFF), g = Double((colour >> 8) & 0xFF), b = Double(colour & 0xFF)
        let grey = UInt32((0.299 * r + 0.587 * g + 0.114 * b) * 0.8)
        return blend(blend(colour, 0, 0.2), grey << 16 | grey << 8 | grey, 0.5)
    }
}
