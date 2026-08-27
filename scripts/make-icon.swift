#!/usr/bin/env swift
//
// Draws Rephraze's app icon and writes Resources/AppIcon.icns.
//
// Generated rather than committed as binary art so it can be tweaked in one
// place and re-rendered at every size macOS asks for. Run: make icon
//
// The mark is a wand crossing a line of text, which is the whole product in one
// picture: your words, rewritten. It matches the menu bar glyph so the app is
// recognisable in both places.

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

    let u = box.width           // work in fractions of the inner box
    func x(_ f: CGFloat) -> CGFloat { box.minX + u * f }
    func y(_ f: CGFloat) -> CGFloat { box.minY + u * f }

    // Two lines of "text", the lower one shorter -- a paragraph, abstracted.
    // Dropped at 16pt, where they would collapse into grey mush.
    if S >= 32 {
        ctx.setFillColor(NSColor(white: 1, alpha: 0.42).cgColor)
        let barHeight = u * 0.052
        let barRadius = barHeight / 2
        for (index, spec) in [(CGFloat(0.30), CGFloat(0.52)), (0.175, 0.40)].enumerated() {
            let rect = CGRect(
                x: x(0.185),
                y: y(spec.0),
                width: u * spec.1,
                height: barHeight
            )
            ctx.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: barRadius, cornerHeight: barRadius, transform: nil
            ))
            ctx.fillPath()
            _ = index
        }
    }

    // The wand: a rounded bar running lower-left to upper-right.
    ctx.saveGState()
    let wandWidth = u * 0.085
    ctx.translateBy(x: box.midX, y: box.midY)
    ctx.rotate(by: -.pi / 4)
    // Length chosen so the tip lands exactly under the big sparkle's centre,
    // which then covers it -- otherwise the bar pokes through the star.
    let wandReach = u * 0.275
    let wand = CGRect(
        x: -wandWidth / 2,
        y: -wandReach,
        width: wandWidth,
        height: wandReach * 2
    )
    ctx.addPath(CGPath(
        roundedRect: wand,
        cornerWidth: wandWidth / 2, cornerHeight: wandWidth / 2, transform: nil
    ))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // MARK: Sparkles

    /// A four-point star with concave sides.
    func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        let waist = r * 0.30            // how pinched the sides are
        path.move(to: CGPoint(x: cx, y: cy + r))
        path.addQuadCurve(
            to: CGPoint(x: cx + r, y: cy),
            control: CGPoint(x: cx + waist, y: cy + waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy - r),
            control: CGPoint(x: cx + waist, y: cy - waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - r, y: cy),
            control: CGPoint(x: cx - waist, y: cy - waist)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: cy + r),
            control: CGPoint(x: cx - waist, y: cy + waist)
        )
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(NSColor(white: 1, alpha: alpha).cgColor)
        ctx.fillPath()
    }

    // The wand runs at -45 degrees from the centre, so its tip is exactly
    // reach/sqrt(2) along both axes. Put the big sparkle there.
    let tipOffset = 0.275 / 2.0.squareRoot()
    sparkle(cx: x(0.5 + tipOffset), cy: y(0.5 + tipOffset), r: u * 0.135, alpha: 1.0)
    if S >= 32 {
        sparkle(cx: x(0.845), cy: y(0.505), r: u * 0.055, alpha: 0.92)
        sparkle(cx: x(0.545), cy: y(0.865), r: u * 0.042, alpha: 0.78)
    }

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
