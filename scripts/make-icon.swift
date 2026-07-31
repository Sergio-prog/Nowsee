import AppKit
import CoreGraphics
import Foundation

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/Nowsee.iconset"

let magmaStops: [SIMD3<Double>] = [
    SIMD3(0.001, 0.000, 0.014),
    SIMD3(0.232, 0.059, 0.437),
    SIMD3(0.550, 0.161, 0.506),
    SIMD3(0.868, 0.288, 0.409),
    SIMD3(0.988, 0.553, 0.383),
    SIMD3(0.987, 0.991, 0.750),
]

let barHeights: [CGFloat] = [0.52, 1.00, 0.74, 0.36]

func magma(_ position: Double) -> SIMD3<Double> {
    let scaled = max(0, min(1, position)) * Double(magmaStops.count - 1)
    let lower = min(Int(scaled), magmaStops.count - 1)
    let upper = min(lower + 1, magmaStops.count - 1)
    let blend = scaled - Double(lower)
    return magmaStops[lower] * (1 - blend) + magmaStops[upper] * blend
}

func color(_ rgb: SIMD3<Double>, _ alpha: Double = 1) -> CGColor {
    CGColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: alpha)
}

func render(size: Int) -> Data {
    let dimension = CGFloat(size)
    guard
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create a \(size)px context") }

    context.setAllowsAntialiasing(true)

    let corner = dimension * 0.2237
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: dimension, height: dimension),
            cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let backdrop = CGGradient(
        colorsSpace: space,
        colors: [
            color(SIMD3(0.129, 0.051, 0.196)), color(SIMD3(0.043, 0.016, 0.071)),
            color(SIMD3(0.012, 0.004, 0.024)),
        ] as CFArray,
        locations: [0, 0.55, 1])!
    context.drawLinearGradient(
        backdrop, start: CGPoint(x: 0, y: dimension), end: CGPoint(x: 0, y: 0), options: [])

    let inset = dimension * 0.17
    let content = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let gapRatio: CGFloat = 0.34
    let barWidth = content.width / (CGFloat(barHeights.count) + gapRatio * CGFloat(barHeights.count - 1))
    let gap = barWidth * gapRatio
    let baselineHeight = max(1, dimension * 0.018)

    context.setFillColor(color(SIMD3(1, 1, 1), 0.22))
    context.fill(
        CGRect(x: content.minX, y: content.minY, width: content.width, height: baselineHeight))

    for (index, fraction) in barHeights.enumerated() {
        let height = max(baselineHeight * 2, content.height * fraction)
        let rect = CGRect(
            x: content.minX + (barWidth + gap) * CGFloat(index),
            y: content.minY,
            width: barWidth,
            height: height)

        let radius = min(barWidth * 0.36, height * 0.5)
        context.saveGState()
        context.addPath(
            CGPath(
                roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()

        let low = magma(0.28 + Double(fraction) * 0.12)
        let high = magma(0.55 + Double(fraction) * 0.42)
        let barGradient = CGGradient(
            colorsSpace: space, colors: [color(low), color(high)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(
            barGradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY),
            options: [])
        context.restoreGState()
    }

    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(SIMD3(1, 1, 1), 0.12), color(SIMD3(1, 1, 1), 0)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        sheen, start: CGPoint(x: 0, y: dimension), end: CGPoint(x: 0, y: dimension * 0.45),
        options: [])

    guard let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fatalError("could not encode a \(size)px image") }
    return data
}

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try FileManager.default.createDirectory(
    atPath: outputDirectory, withIntermediateDirectories: true)

for variant in variants {
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(variant.name).png")
    try render(size: variant.size).write(to: url)
}

print("wrote \(variants.count) images to \(outputDirectory)")
