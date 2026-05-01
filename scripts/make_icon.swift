#!/usr/bin/env swift

// Generates build/AppIcon.icns from the design-system duck-in-pond mark
// composited onto a cream rounded square. The mark loads from
// `Sources/OpenQuackApp/Resources/Brand/duck-in-pond@2x.png` so the icon
// stays in lockstep with whatever ships in the app bundle.
//
// At small icon sizes (16/32 pt) the line art gets thin; we counter by
// drawing the mark at higher logical width than at large sizes — see the
// per-size scale curve below.

import AppKit
import Foundation

let cwd = FileManager.default.currentDirectoryPath
let buildDir   = URL(fileURLWithPath: cwd).appendingPathComponent("build")
let iconsetDir = buildDir.appendingPathComponent("AppIcon.iconset")
let icnsURL    = buildDir.appendingPathComponent("AppIcon.icns")
let markURL    = URL(fileURLWithPath: cwd)
    .appendingPathComponent("Sources/OpenQuackApp/Resources/Brand/duck-in-pond@2x.png")

guard let mark = NSImage(contentsOf: markURL) else {
    print("error: brand mark missing at \(markURL.path)")
    exit(1)
}

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: buildDir,   withIntermediateDirectories: true)

// Cream tones — match Theme.swift / `--oq-cream` from the design system.
let creamTop    = NSColor(srgbRed: 0.969, green: 0.957, blue: 0.929, alpha: 1.0)  // #F7F4ED
let creamBottom = NSColor(srgbRed: 0.910, green: 0.875, blue: 0.788, alpha: 1.0)  // #E8DFC9 (creamRaised)

// Scale curve: bigger marks at small canvases so the line weight reads,
// smaller marks at large canvases for proper "icon" breathing room.
func markScale(side: CGFloat) -> CGFloat {
    switch side {
    case ..<48:   return 0.92
    case ..<128:  return 0.86
    case ..<512:  return 0.80
    default:      return 0.76
    }
}

func renderIcon(side: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus()
    defer { img.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let cornerRadius = side * 0.22

    // Cream gradient bg.
    let gradient = NSGradient(starting: creamTop, ending: creamBottom)!
    let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: bg, angle: -90)

    // Inner hairline rim — gives the icon a subtle crisp edge.
    NSColor.black.withAlphaComponent(0.06).setStroke()
    let inset = NSBezierPath(
        roundedRect: rect.insetBy(dx: max(1, side * 0.008), dy: max(1, side * 0.008)),
        xRadius: cornerRadius * 0.96, yRadius: cornerRadius * 0.96
    )
    inset.lineWidth = max(1, side * 0.010)
    inset.stroke()

    // Composite the duck-in-pond mark, centred, preserving its native aspect.
    let scale = markScale(side: side)
    let markAspect = mark.size.width / max(mark.size.height, 1)
    let markW = side * scale
    let markH = markW / markAspect
    let markRect = NSRect(
        x: (side - markW) / 2,
        y: (side - markH) / 2,
        width: markW,
        height: markH
    )
    mark.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    return img
}

func writePNG(_ image: NSImage, side: Int, name: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { throw NSError(domain: "make_icon", code: 1) }
    rep.size = NSSize(width: side, height: side)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 2)
    }
    try png.write(to: iconsetDir.appendingPathComponent(name))
    print("  ✓ \(name) (\(side)×\(side))")
}

// .iconset canonical filename × size table.
let layouts: [(side: Int, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

print("→ Rendering \(layouts.count) sizes from duck-in-pond mark...")
for layout in layouts {
    let img = renderIcon(side: CGFloat(layout.side))
    try writePNG(img, side: layout.side, name: layout.name)
}

print("→ Packing AppIcon.icns...")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["--convert", "icns", iconsetDir.path, "--output", icnsURL.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else {
    print("error: iconutil failed (code \(p.terminationStatus))")
    exit(1)
}

print("✓ \(icnsURL.path)")
try? FileManager.default.removeItem(at: iconsetDir)
