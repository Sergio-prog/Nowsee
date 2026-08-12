import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "web/public/og.png"

let width = 1200
let height = 630
let bands = 96
let columns = 400
let harmonics = 15

let magmaStops: [SIMD3<Double>] = [
    SIMD3(0.001, 0.000, 0.014),
    SIMD3(0.232, 0.059, 0.437),
    SIMD3(0.550, 0.161, 0.506),
    SIMD3(0.868, 0.288, 0.409),
    SIMD3(0.988, 0.553, 0.383),
    SIMD3(0.987, 0.991, 0.750),
]

struct Partial {
    let centre: Double
    let width: Double
    let gain: Double
    let drift: Double
    let rate: Double
    let beat: Double
}

let partials: [Partial] = [
    Partial(centre: 0.04, width: 0.045, gain: 1.0, drift: 0.31, rate: 0.44, beat: 1.0),
    Partial(centre: 0.26, width: 0.075, gain: 0.5, drift: 0.83, rate: 0.27, beat: 0.3),
    Partial(centre: 0.52, width: 0.095, gain: 0.34, drift: 1.27, rate: 0.61, beat: 0.1),
    Partial(centre: 0.78, width: 0.13, gain: 0.22, drift: 1.91, rate: 0.38, beat: 0.05),
]

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

func noise(_ n: Double) -> Double {
    let s = sin(n * 127.1 + 31.7) * 43758.5453
    return s - floor(s)
}

func addPeak(_ target: inout [Double], _ centre: Double, _ amp: Double, _ width: Double) {
    if centre > 1.04 || amp < 0.004 { return }
    let spread = 1 / (2 * width * width)
    let from = max(0, Int(floor((centre - width * 3) * Double(bands - 1))))
    let to = min(bands - 1, Int(ceil((centre + width * 3) * Double(bands - 1))))
    if from > to { return }
    for b in from...to {
        let d = Double(b) / Double(bands - 1) - centre
        target[b] += amp * exp(-d * d * spread)
    }
}

func spectrogramHistory() -> [[Double]] {
    var smooth = [Double](repeating: 0, count: bands)
    var history = [[Double]]()
    var clock = 0.0
    let dt = 1.0 / 30.0

    for step in 0..<(columns * 2) {
        clock += dt
        let beat = (clock * 108 / 60).truncatingRemainder(dividingBy: 1)
        let hit = exp(-beat * 5.5)
        let bar = exp(-(clock * 27 / 60).truncatingRemainder(dividingBy: 1) * 3.2)

        var left = [Double](repeating: 0, count: bands)

        for p in partials {
            let wander = sin(clock * p.drift) * 0.05 + sin(clock * p.drift * 0.41) * 0.028
            let breath = 0.55 + 0.45 * sin(clock * p.rate + p.centre * 9)
            let amp = p.gain * (0.34 + 0.66 * breath) * (1 - p.beat * 0.55 + p.beat * hit * 1.5)
            addPeak(&left, p.centre + wander, amp, p.width)
        }

        let root = 0.052 + 0.016 * sin(clock * 0.19) + 0.008 * sin(clock * 0.53)
        for h in 1...harmonics {
            let centre = root * Double(h) * (1 + 0.006 * Double(h))
            let voice = 0.62 + 0.38 * sin(clock * (0.4 + Double(h) * 0.11) + Double(h) * 1.7)
            let amp = (0.66 / pow(Double(h), 0.78)) * voice * (0.7 + 0.3 * hit)
            let width = 0.009 + 0.0035 * Double(h)
            addPeak(&left, centre, amp, width)
        }

        for b in 0..<bands {
            let x = Double(b) / Double(bands - 1)
            let air = 0.05 * (1 - x)
            let sizzle = x > 0.5 ? 0.16 * bar * hit * noise(Double(b) + floor(clock * 14)) : 0
            left[b] = min(1, max(0, left[b] * 0.56 + air + sizzle))
            smooth[b] += (left[b] - smooth[b]) * 0.34
        }

        if step >= columns { history.append(left) }
    }

    return history
}

func contrastStretched(_ history: [[Double]]) -> [[Double]] {
    let levels = history.flatMap { $0 }.sorted()
    let ceiling = max(0.08, levels[Int(Double(levels.count - 1) * 0.985)])
    let floor = levels[Int(Double(levels.count - 1) * 0.30)]
    let span = max(0.04, ceiling - floor)
    return history.map { $0.map { max(0, min(1, ($0 - floor) / span)) } }
}

func spectrogramImage(_ history: [[Double]]) -> CGImage {
    guard
        let context = CGContext(
            data: nil, width: columns, height: bands, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create the spectrogram context") }

    guard let pixels = context.data else { fatalError("no spectrogram backing store") }
    let buffer = pixels.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * bands)

    for x in 0..<columns {
        let column = history[x]
        for y in 0..<bands {
            let rgb = magma(column[y])
            let offset = (bands - 1 - y) * context.bytesPerRow + x * 4
            buffer[offset] = UInt8(max(0, min(255, rgb.x * 255)))
            buffer[offset + 1] = UInt8(max(0, min(255, rgb.y * 255)))
            buffer[offset + 2] = UInt8(max(0, min(255, rgb.z * 255)))
            buffer[offset + 3] = 255
        }
    }

    guard let image = context.makeImage() else { fatalError("could not read the spectrogram") }
    return image
}

func draw(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, tracking: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}

let canvasSize = CGSize(width: CGFloat(width), height: CGFloat(height))
guard
    let canvas = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create the canvas") }

let space = CGColorSpaceCreateDeviceRGB()

canvas.setFillColor(color(SIMD3(0.031, 0.027, 0.051)))
canvas.fill(CGRect(origin: .zero, size: canvasSize))

let halo = CGGradient(
    colorsSpace: space,
    colors: [color(SIMD3(0.550, 0.161, 0.506), 0.34), color(SIMD3(0.550, 0.161, 0.506), 0)]
        as CFArray,
    locations: [0, 1])!
canvas.drawRadialGradient(
    halo, startCenter: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 1.06),
    startRadius: 0, endCenter: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 1.06),
    endRadius: canvasSize.width * 0.66, options: [])

let margin: CGFloat = 78
let stage = CGRect(x: margin, y: 74, width: canvasSize.width - margin * 2, height: 268)

canvas.saveGState()
canvas.setShadow(
    offset: CGSize(width: 0, height: -26), blur: 64,
    color: color(SIMD3(0.550, 0.161, 0.506), 0.55))
canvas.setFillColor(color(SIMD3(0, 0, 0)))
canvas.addPath(CGPath(roundedRect: stage, cornerWidth: 16, cornerHeight: 16, transform: nil))
canvas.fillPath()
canvas.restoreGState()

canvas.saveGState()
canvas.addPath(CGPath(roundedRect: stage, cornerWidth: 16, cornerHeight: 16, transform: nil))
canvas.clip()
canvas.interpolationQuality = .high
canvas.draw(spectrogramImage(contrastStretched(spectrogramHistory())), in: stage)
canvas.restoreGState()

canvas.setStrokeColor(color(SIMD3(1, 1, 1), 0.1))
canvas.setLineWidth(1)
canvas.addPath(
    CGPath(roundedRect: stage.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 16, cornerHeight: 16, transform: nil))
canvas.strokePath()

let graphics = NSGraphicsContext(cgContext: canvas, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

draw(
    "Nowsee",
    at: CGPoint(x: margin, y: 434),
    font: NSFont.systemFont(ofSize: 112, weight: .semibold),
    color: NSColor(red: 0.937, green: 0.929, blue: 0.961, alpha: 1),
    tracking: -4.0)

draw(
    "Draws whatever your Mac is playing, as it plays.",
    at: CGPoint(x: margin + 4, y: 374),
    font: NSFont.systemFont(ofSize: 36, weight: .regular),
    color: NSColor(red: 0.62, green: 0.61, blue: 0.68, alpha: 1),
    tracking: -0.4)

draw(
    "LIVE SYSTEM AUDIO · MACOS · FREE AND OPEN SOURCE",
    at: CGPoint(x: margin + 5, y: 528),
    font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium),
    color: NSColor(red: 0.988, green: 0.553, blue: 0.383, alpha: 0.94),
    tracking: 2.5)

NSGraphicsContext.restoreGraphicsState()

guard let image = canvas.makeImage(),
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("could not encode the image") }

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: url)

print("wrote \(width)x\(height) to \(outputPath)")
