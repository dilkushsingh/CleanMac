#!/usr/bin/env swift
// Renders the CleanMac AppIcon.appiconset from the same tile design as AboutIcon.
// Run once (or whenever the design changes):
//   swift scripts/generate-appicon.swift

import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func render(size: CGFloat) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .regular)
        .applying(.init(paletteColors: [.systemTeal, .systemBlue]))
    let symbol = NSImage(systemSymbolName: "bubbles.and.sparkles.fill",
                         accessibilityDescription: "CleanMac")?
        .withSymbolConfiguration(cfg) ?? NSImage()

    return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
        NSGradient(colors: [NSColor(white: 0.14, alpha: 1),
                            NSColor(white: 0.04, alpha: 1)])?
            .draw(in: path, angle: -90)
        let s = symbol.size
        symbol.draw(in: NSRect(
            x: (size - s.width) / 2,
            y: (size - s.height) / 2,
            width: s.width, height: s.height
        ))
        return true
    }
}

func png(_ image: NSImage, _ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root
    .appendingPathComponent("CleanMac/Assets.xcassets/AppIcon.appiconset")

try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let img = render(size: CGFloat(px))
    try png(img, px).write(to: iconset.appendingPathComponent(name))
    print("wrote \(name) (\(px)x\(px))")
}

let contents = """
{
  "images" : [
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16.png",       "scale" : "1x" },
    { "size" : "16x16",   "idiom" : "mac", "filename" : "icon_16x16@2x.png",    "scale" : "2x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32.png",       "scale" : "1x" },
    { "size" : "32x32",   "idiom" : "mac", "filename" : "icon_32x32@2x.png",    "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png",     "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png",  "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png",     "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png",  "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png",     "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png",  "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try contents.write(
    to: iconset.appendingPathComponent("Contents.json"),
    atomically: true, encoding: .utf8
)
print("wrote Contents.json")

let catalogContents = """
{ "info" : { "version" : 1, "author" : "xcode" } }
"""
let catalogRoot = root.appendingPathComponent("CleanMac/Assets.xcassets")
try catalogContents.write(
    to: catalogRoot.appendingPathComponent("Contents.json"),
    atomically: true, encoding: .utf8
)
print("done")
