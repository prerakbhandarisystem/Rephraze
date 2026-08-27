#!/usr/bin/env swift
//
// Draws Rephraze's app icon and writes Resources/AppIcon.icns.
//
// Generated rather than committed as binary art so it can be tweaked in one
// place and re-rendered at every size macOS asks for. Run: make icon
//
// The mark is one stroke that starts jagged and resolves into a smooth curve:
// rough writing in, clean writing out. Abstract on purpose -- it stays legible
// at 16pt and does not compete with the literal wand in the menu bar, which is
// a different job at a different size.

import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func draw(size S: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icons sit inside the canvas rather than filling it.
    let inset = S * 0.0977
    let box = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = box.width * 0.2237      // Big Sur squircle ratio
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Body: indigo into violet, lit from the top.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.42, green: 0.42, blue: 0.96, alpha: 1).cgColor,
        NSColor(srgbRed: 0.61, green: 0.33, blue: 0.94, alpha: 1).cgColor,
        NSColor(srgbRed: 0.72, green: 0.29, blue: 0.87, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY),
        options: []
    )

    // A soft sheen across the top third, so it does not read as flat plastic.
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1, alpha: 0.22).cgColor,
            NSColor(white: 1, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: box.midX, y: box.maxY),
        end: CGPoint(x: box.midX, y: box.midY),
        options: []
    )
    ctx.restoreGState()

    // Hairline edge for definition on light and dark backgrounds alike.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.20).cgColor)
    ctx.setLineWidth(max(0.75, S * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // MARK: The mark
    //
    // One continuous stroke that begins as hard angular zigzag and resolves
    // into a smooth curve. That is the product in a single form: rough writing
    // going in, clean writing coming out. No wand, no text lines, no sparkles --
    // an abstract mark reads at 16pt and does not date, where an illustration
    // turns to mush and looks like every other AI app.

    let u = box.width           // work in fractions of the inner box
    func x(_ f: CGFloat) -> CGFloat { box.minX + u * f }
    func y(_ f: CGFloat) -> CGFloat { box.minY + u * f }

    // A damped wave: one continuous stroke that starts as a wide oscillation
    // and settles almost flat. That is rephrasing -- the same line throughout,
    // the same direction, just resolved by the end.
    //
    // Earlier attempts used hard mitred corners for the "rough" half. They
    // produced spikes and read as a heartbeat, which is a different product
    // entirely. Amplitude carries the meaning here; sharpness does not.
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: x(0.130), y: y(0.500)))

    /// One half-oscillation, flat-to-flat, bulging by `amplitude`.
    func wave(to endX: CGFloat, amplitude: CGFloat) {
        let startX = mark.currentPoint.x
        let span = endX - startX
        mark.addCurve(
            to: CGPoint(x: endX, y: y(0.500)),
            control1: CGPoint(x: startX + span * 0.36, y: y(0.500) - box.minY + box.minY + amplitude),
            control2: CGPoint(x: endX - span * 0.36, y: y(0.500) + amplitude)
        )
    }

    wave(to: x(0.315), amplitude: u * 0.290)    // wide
    wave(to: x(0.500), amplitude: -u * 0.245)
    wave(to: x(0.675), amplitude: u * 0.145)    // narrowing
    wave(to: x(0.875), amplitude: -u * 0.048)   // settles level, no final kink

    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(u * 0.098)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if S >= 128 {
        ctx.setShadow(
            offset: CGSize(width: 0, height: -S * 0.008),
            blur: S * 0.020,
            color: NSColor(white: 0, alpha: 0.18).cgColor
        )
    }

    ctx.addPath(mark)
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// MARK: - Write the iconset

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// macOS wants each size at 1x and 2x, named exactly like this.
var written = 0
for size in sizes {
    let image = draw(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }

    try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    written += 1

    // The 2x slot of the next size down is the same pixel count.
    if size > 16 {
        let half = size / 2
        try png.write(to: iconset.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()

guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("Wrote \(out.path) from \(written) sizes")
