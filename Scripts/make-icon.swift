#!/usr/bin/env swift
//
// Renders GlassDeck's app icon at every size macOS asks for and packs the result
// into an .icns. Keeping the icon as code means it can be regenerated on any
// machine without shipping binary art in the repository.
//
import AppKit
import Foundation

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

/// Draws the icon into the current context at `size` × `size`.
func drawIcon(size: CGFloat, context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.235

    // Squircle body: deep blue glass.
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(squircle)
    context.clip()

    let backdrop = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.09, green: 0.12, blue: 0.26, alpha: 1),
            CGColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        backdrop,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )

    // Specular sweep across the top third, the giveaway of a glass surface.
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY),
        options: []
    )
    context.restoreGState()

    // Gauge ring at 72%, sweeping cyan → violet.
    let centre = CGPoint(x: rect.midX, y: rect.midY + size * 0.02)
    let ringRadius = size * 0.27
    let ringWidth = size * 0.085

    context.setLineCap(.round)
    context.setLineWidth(ringWidth)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.addArc(center: centre, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    context.saveGState()
    context.setLineWidth(ringWidth)
    context.addArc(
        center: centre,
        radius: ringRadius,
        startAngle: .pi / 2,
        endAngle: .pi / 2 - .pi * 1.44,
        clockwise: true
    )
    context.replacePathWithStrokedPath()
    context.clip()
    let arc = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.25, green: 0.85, blue: 1.0, alpha: 1),
            CGColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        arc,
        start: CGPoint(x: centre.x - ringRadius, y: centre.y - ringRadius),
        end: CGPoint(x: centre.x + ringRadius, y: centre.y + ringRadius),
        options: []
    )
    context.restoreGState()

    // Three level bars inside the ring: the metric deck in miniature.
    let barWidth = size * 0.052
    let spacing = size * 0.035
    let heights: [CGFloat] = [0.16, 0.26, 0.2]
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
    var x = centre.x - totalWidth / 2

    for height in heights {
        let barRect = CGRect(x: x, y: centre.y - size * 0.13, width: barWidth, height: size * height)
        let bar = CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        )
        context.addPath(bar)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        context.fillPath()
        x += barWidth + spacing
    }
}

func makePNG(size: Int) -> Data {
    let scale = 1
    let pixels = size * scale
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(size: CGFloat(pixels), context: context)
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: pixels, height: pixels)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = outputDirectory.appendingPathComponent("GlassDeck.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The names below are the exact set `iconutil` expects.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let data = makePNG(size: variant.size)
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

print("Wrote \(iconset.path)")
