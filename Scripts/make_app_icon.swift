#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

// Generates the 1024x1024 macOS app-icon master from the brand mark
// (the neon-cyan bot-in-speech-bubble used in the menu bar). The mark is
// composited onto a dark Tahoe-style squircle with a cyan neon glow, which
// turns the upscale softness of the small source mark into an intentional
// glow aesthetic. Output feeds `iconutil` in Scripts/package_app.sh.
//
// Usage: swift Scripts/make_app_icon.swift <mark.png> <out-1024.png>

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make_app_icon.swift <mark.png> <out.png>\n".utf8))
    exit(2)
}

let markURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let markImage = NSImage(contentsOf: markURL),
      let markCG = markImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("could not load mark image\n".utf8))
    exit(1)
}

let side = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("could not create context\n".utf8))
    exit(1)
}

ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

// macOS Big Sur icon grid: the rounded-rect body is inset from the 1024 canvas
// so the icon reads correctly next to first-party apps.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let radius = body.width * 0.2237
let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Soft drop shadow so the icon floats like a native one.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: color(0, 0, 0, 0.55))
ctx.addPath(squircle)
ctx.setFillColor(color(0.04, 0.09, 0.16, 1))
ctx.fillPath()
ctx.restoreGState()

// Background gradient: deep space navy with a cyan undertone.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bg = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0.07, 0.18, 0.30), color(0.03, 0.08, 0.15)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    bg,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY),
    options: [])

/// Radial cyan bloom behind the mark for depth.
let bloom = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0.30, 0.85, 1.0, 0.42), color(0.30, 0.85, 1.0, 0.0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(
    bloom,
    startCenter: CGPoint(x: body.midX, y: body.midY + 20),
    startRadius: 0,
    endCenter: CGPoint(x: body.midX, y: body.midY + 20),
    endRadius: body.width * 0.52,
    options: [])

// Subtle top rim highlight for the glassy Tahoe finish.
ctx.addPath(CGPath(
    roundedRect: body.insetBy(dx: 3, dy: 3),
    cornerWidth: radius - 3,
    cornerHeight: radius - 3,
    transform: nil))
ctx.setStrokeColor(color(1, 1, 1, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

/// Pre-scale the small source mark once with high-quality interpolation so its
/// alpha edges are smooth. `clip(to:mask:)` does not interpolate, so masking with
/// the raw 44px image would leave visible pixel stair-stepping in the recolor.
let markPixels = 720
guard let markCtx = CGContext(
    data: nil,
    width: markPixels,
    height: markPixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("could not create mark context\n".utf8))
    exit(1)
}

markCtx.interpolationQuality = .high
markCtx.draw(markCG, in: CGRect(x: 0, y: 0, width: markPixels, height: markPixels))
let smoothMark = markCtx.makeImage() ?? markCG

// The mark: recolored to a bright, uniform cyan and given a neon glow.
let markSide: CGFloat = 520
let markRect = CGRect(
    x: (CGFloat(side) - markSide) / 2,
    y: (CGFloat(side) - markSide) / 2 + 8,
    width: markSide,
    height: markSide)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: color(0.35, 0.88, 1.0, 0.85))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.draw(smoothMark, in: markRect)
// Repaint the mark pixels with a vivid cyan gradient, preserving their shape.
ctx.setBlendMode(.sourceAtop)
ctx.clip(to: markRect, mask: smoothMark)
let inkTop = color(0.62, 0.95, 1.0)
let inkBottom = color(0.20, 0.78, 1.0)
let ink = CGGradient(colorsSpace: colorSpace, colors: [inkTop, inkBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    ink,
    start: CGPoint(x: markRect.midX, y: markRect.maxY),
    end: CGPoint(x: markRect.midX, y: markRect.minY),
    options: [])
ctx.endTransparencyLayer()
ctx.restoreGState()

guard let out = ctx.makeImage() else {
    FileHandle.standardError.write(Data("could not render image\n".utf8))
    exit(1)
}

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("could not create destination\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("could not write png\n".utf8))
    exit(1)
}

print("wrote \(outURL.path)")
