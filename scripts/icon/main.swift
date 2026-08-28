//
// Draws Rephraze's app icon and writes Resources/AppIcon.icns.
//
// Generated rather than committed as binary art so it can be tweaked in one
// place and re-rendered at every size macOS asks for. Run: make icon
//
// The mark itself lives in the app, in RephrazeKit/UI/RephrazeMark.swift, which
// scripts/make-icon.sh compiles alongside this file. The icon, the menu bar and
// the panel all stroke that one path -- when it was defined here instead, the
// app kept a wand in the menu bar for a release after the icon stopped being one.

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

    // Drawn in the app's own coordinates -- y down, as SwiftUI has it -- so the
    // shared path needs flipping into Core Graphics' y-up canvas. Flipping the
    // path rather than the context leaves the shadow below the stroke, where a
    // flipped context would put it above.
    var flip = CGAffineTransform(translationX: 0, y: S).scaledBy(x: 1, y: -1)
    let mark = RephrazeMark().path(in: box).cgPath.copy(using: &flip)!

    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(box.width * RephrazeMark.strokeWidthRatio)
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
