#!/usr/bin/env swift

// Generates build/AppIcon.icns from a procedural design — warm cream gradient
// rounded square with a 🦆 mark centred. Replaces the system "no icon" with
// something on-brand for v0; bespoke art can drop into the same path later
// (just produce a build/AppIcon.iconset and rerun iconutil).

import AppKit
import Foundation

let cwd = FileManager.default.currentDirectoryPath
let buildDir = URL(fileURLWithPath: cwd).appendingPathComponent("build")
let iconsetDir = buildDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = buildDir.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

func renderIcon(side: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus()
    defer { img.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    let cornerRadius = side * 0.22

    // Warm cream → soft amber gradient.
    let top    = NSColor(srgbRed: 1.00, green: 0.94, blue: 0.74, alpha: 1.0)
    let bottom = NSColor(srgbRed: 0.96, green: 0.78, blue: 0.36, alpha: 1.0)
    let gradient = NSGradient(starting: top, ending: bottom)!
    let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: bg, angle: -90)

    // Inner hairline for a slight rim.
    NSColor.black.withAlphaComponent(0.08).setStroke()
    let inset = NSBezierPath(
        roundedRect: rect.insetBy(dx: max(1, side * 0.008), dy: max(1, side * 0.008)),
        xRadius: cornerRadius * 0.96, yRadius: cornerRadius * 0.96
    )
    inset.lineWidth = max(1, side * 0.01)
    inset.stroke()

    // Soft drop-shadow for the glyph so it lifts off the gradient.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = side * 0.04
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.set()

    // 🦆 centred. Use a font size relative to icon side — leaves margin for the rim.
    let emojiSize = side * 0.66
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: emojiSize),
        .paragraphStyle: para,
    ]
    let glyph = NSAttributedString(string: "🦆", attributes: attrs)
    let glyphSize = glyph.size()
    let origin = NSPoint(
        x: (side - glyphSize.width) / 2,
        y: (side - glyphSize.height) / 2 - side * 0.03  // shifted down slightly for visual balance
    )
    glyph.draw(at: origin)

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

print("→ Rendering \(layouts.count) sizes...")
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

// Tidy the intermediate iconset; the .icns is the only durable artefact.
try? FileManager.default.removeItem(at: iconsetDir)
