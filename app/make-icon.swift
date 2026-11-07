// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 homecla

// Generates the app icon (PNG 1024×1024): swift make-icon.swift output.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: macOS-style rounded square with a burgundy gradient
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(red: 0.45, green: 0.07, blue: 0.16, alpha: 1).setFill(); shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()
NSGradient(colors: [NSColor(red: 0.72, green: 0.16, blue: 0.27, alpha: 1),
                    NSColor(red: 0.36, green: 0.04, blue: 0.13, alpha: 1)])!.draw(in: shape, angle: -90)

// Hand-drawn decanter. Original artwork: Apple's SF Symbols may not be used in app icons,
// and no third-party logos are used.
let cx = size / 2
let white = NSColor.white

// Decanter outline: wide flat-bottomed body, narrow neck, flared lip
let body = NSBezierPath()
body.move(to: NSPoint(x: cx - 205, y: 262))                       // bottom left
body.line(to: NSPoint(x: cx + 205, y: 262))                       // flat base
body.curve(to: NSPoint(x: cx + 285, y: 410),
           controlPoint1: NSPoint(x: cx + 265, y: 262), controlPoint2: NSPoint(x: cx + 290, y: 330))
body.curve(to: NSPoint(x: cx + 58, y: 615),
           controlPoint1: NSPoint(x: cx + 290, y: 575), controlPoint2: NSPoint(x: cx + 62, y: 560))
body.line(to: NSPoint(x: cx + 48, y: 750))                        // neck, right side
body.curve(to: NSPoint(x: cx + 92, y: 800),
           controlPoint1: NSPoint(x: cx + 48, y: 775), controlPoint2: NSPoint(x: cx + 92, y: 780))
body.line(to: NSPoint(x: cx - 92, y: 800))                        // lip
body.curve(to: NSPoint(x: cx - 48, y: 750),
           controlPoint1: NSPoint(x: cx - 92, y: 780), controlPoint2: NSPoint(x: cx - 48, y: 775))
body.line(to: NSPoint(x: cx - 58, y: 615))                        // neck, left side
body.curve(to: NSPoint(x: cx - 285, y: 410),
           controlPoint1: NSPoint(x: cx - 62, y: 560), controlPoint2: NSPoint(x: cx - 290, y: 575))
body.curve(to: NSPoint(x: cx - 205, y: 262),
           controlPoint1: NSPoint(x: cx - 290, y: 330), controlPoint2: NSPoint(x: cx - 265, y: 262))
body.close()
white.setFill(); body.fill()

// Wine in the lower part of the body, in a darker burgundy
NSGraphicsContext.current?.saveGraphicsState()
body.addClip()
let wineTop: CGFloat = 445
let wine = NSBezierPath()
wine.move(to: NSPoint(x: cx - 320, y: wineTop))
wine.curve(to: NSPoint(x: cx + 320, y: wineTop),
           controlPoint1: NSPoint(x: cx - 110, y: wineTop + 26), controlPoint2: NSPoint(x: cx + 110, y: wineTop - 26))
wine.line(to: NSPoint(x: cx + 320, y: 240))
wine.line(to: NSPoint(x: cx - 320, y: 240))
wine.close()
NSColor(red: 0.50, green: 0.06, blue: 0.18, alpha: 1).setFill(); wine.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
