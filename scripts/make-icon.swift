#!/usr/bin/env swift
//
// make-icon.swift — render the Marin Viewer logo into every standard macOS icon size.
//
//   swift scripts/make-icon.swift Resources/marin-viewer-logo.svg
//
// The Makefile passes ICON_SOURCE and packages the PNGs with iconutil.
//
// The logo is a circle: a cream ring around a dark disc that holds the sailboat. macOS 26 and
// later shrink an icon that does not fill the app-icon squircle onto a grey plate, so the
// icon is laid out on Apple's 1024-point grid instead. An 824-point continuous-corner squircle
// with a cream rim takes the ring's place, its face is the disc's dark blue, and the disc and
// boat sit inside it at the size where the disc spans the face. The squircle carries the
// standard soft drop shadow, which the system does not add to an .icns.
//
// rsvg-convert (Homebrew `librsvg`) renders the logo afresh at each pixel size, so nothing is
// downsampled. NSImage is not used because its CoreSVG renderer drops the logo's glow filter.

import AppKit
import SwiftUI

let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)

func iconError(_ message: String) -> NSError {
    NSError(domain: "MarinViewer.AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

guard CommandLine.arguments.count == 2 else { throw iconError("usage: make-icon.swift <logo.svg>") }
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw iconError("no logo at \(sourceURL.path)") }

// The logo's own geometry (its viewBox and the two circles that draw the ring), in logo units.
let logoCanvas = 1396.0
let ringOuterRadius = 681.22
let discRadius = 639.638

// Apple's macOS app-icon grid, in points on a 1024-point canvas.
let grid = 1024.0
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyCornerRadius = 185.4
// The rim is as thick, relative to the squircle, as the ring is relative to the logo's circle.
let rim = body.width * (ringOuterRadius - discRadius) / (2 * ringOuterRadius)
let face = body.insetBy(dx: rim, dy: rim)
// Size the logo so its dark disc is exactly as wide as the face.
let logoSize = face.width * logoCanvas / (2 * discRadius)

let cream = CGColor(srgbRed: 0xDF / 255.0, green: 0xCF / 255.0, blue: 0xB8 / 255.0, alpha: 1)
let night = CGColor(srgbRed: 0x21 / 255.0, green: 0x2B / 255.0, blue: 0x33 / 255.0, alpha: 1)

func squircle(_ rect: CGRect, radius: Double) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

/// Renders the logo to a PNG of `pixels` square with rsvg-convert and loads it.
func renderLogo(pixels: Int, scratch: URL) throws -> CGImage {
    let out = scratch.appendingPathComponent("logo-\(pixels).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["rsvg-convert", "--width", "\(pixels)", "--height", "\(pixels)",
                      "--output", out.path, sourceURL.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw iconError("rsvg-convert failed (status \(task.terminationStatus)); install it with `brew install librsvg`")
    }
    guard let source = CGImageSourceCreateWithURL(out as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw iconError("could not read the rendered logo \(out.path)")
    }
    return image
}

func renderIcon(pixels: Int, scratch: URL) throws -> Data {
    let scale = Double(pixels) / grid
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw iconError("could not create a \(pixels)px bitmap")
    }
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)

    // The squircle and its shadow. Shadow offset and blur are in device pixels, not points.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                      color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(squircle(body, radius: bodyCornerRadius))
    context.setFillColor(cream)
    context.fillPath()
    context.restoreGState()

    let facePath = squircle(face, radius: bodyCornerRadius - rim)
    context.addPath(facePath)
    context.setFillColor(night)
    context.fillPath()

    // The logo, clipped to the face and to just inside its own disc so the ring stays out.
    // Keep the margin even so the logo sits exactly on the icon's centre; half a pixel off and
    // the clip below lets a sliver of the ring through on one side.
    var logoPixels = max(1, Int((logoSize * scale).rounded()))
    if (pixels - logoPixels) % 2 != 0 { logoPixels += 1 }
    let logo = try renderLogo(pixels: logoPixels, scratch: scratch)
    let discPoints = discRadius / logoCanvas * Double(logoPixels) / scale - 1 / scale
    context.saveGState()
    context.addPath(facePath)
    context.clip()
    context.addEllipse(in: CGRect(x: grid / 2 - discPoints, y: grid / 2 - discPoints,
                                  width: 2 * discPoints, height: 2 * discPoints))
    context.clip()
    // Draw in device pixels at a whole-pixel origin so the rendered logo is not resampled.
    context.scaleBy(x: 1 / scale, y: 1 / scale)
    let origin = Double((pixels - logoPixels) / 2)
    context.draw(logo, in: CGRect(x: origin, y: origin, width: Double(logoPixels), height: Double(logoPixels)))
    context.restoreGState()

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw iconError("could not encode the \(pixels)px icon")
    }
    return png
}

// (filename, pixel dimension) — the complete set iconutil expects.
let variants: [(String, Int)] = [
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

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("marin-viewer-icon-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (name, pixels) in variants {
    try renderIcon(pixels: pixels, scratch: scratch).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}

print("✓ wrote \(variants.count) icons from \(sourceURL.lastPathComponent) to \(iconsetURL.path)")
