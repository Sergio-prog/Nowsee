import Foundation
import NowseeCore
import simd

let bandCount = 128
let windowSize = 2048
let sampleRate: Double = 48000

var failures = 0

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    let mark = passed ? "ok  " : "FAIL"
    print("\(mark) \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !passed { failures += 1 }
}

final class Harness {
    let left = AudioRingBuffer(capacity: 1 << 15)
    let right = AudioRingBuffer(capacity: 1 << 15)
    let analyzer: StereoSpectrumAnalyzer
    private var written = 0

    init() {
        analyzer = StereoSpectrumAnalyzer(
            left: left, right: right, sampleRate: sampleRate, bandCount: bandCount,
            windowSize: windowSize)
    }

    func write(_ count: Int, _ generator: (Int) -> (Float, Float)) {
        var leftSamples = [Float](repeating: 0, count: count)
        var rightSamples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            (leftSamples[index], rightSamples[index]) = generator(written + index)
        }
        leftSamples.withUnsafeBufferPointer { left.write($0.baseAddress!, count) }
        rightSamples.withUnsafeBufferPointer { right.write($0.baseAddress!, count) }
        written += count
    }

    var frameInterval: Float = 1.0 / 60

    func snapshot() -> [SIMD4<Float>]? {
        var result: [SIMD4<Float>]?
        analyzer.snapshot(elapsed: frameInterval) { levels in result = levels }
        return result
    }

    func settle(_ rounds: Int, _ count: Int, _ generator: (Int) -> (Float, Float)) -> [SIMD4<Float>] {
        var latest: [SIMD4<Float>] = []
        for _ in 0..<rounds {
            write(count, generator)
            if let levels = snapshot() { latest = levels }
        }
        return latest
    }
}

func tone(_ hz: Double, _ amplitude: Float) -> (Int) -> Float {
    { index in sin(Float(Double(index) * 2 * .pi * hz / sampleRate)) * amplitude }
}

func peakBand(_ levels: [SIMD4<Float>], _ channel: Int) -> Int {
    var best = 0
    for index in levels.indices where levels[index][channel] > levels[best][channel] {
        best = index
    }
    return best
}

print("nowsee-check — stereo spectrum verification\n")

do {
    let harness = Harness()
    harness.write(windowSize / 2) { _ in (0.5, 0.5) }
    check("no emission before a full window", harness.snapshot() == nil)
}

do {
    let harness = Harness()
    let low = tone(200, 0.6)
    let high = tone(4000, 0.6)
    let levels = harness.settle(40, windowSize) { index in (low(index), high(index)) }

    let leftBand = peakBand(levels, 0)
    let rightBand = peakBand(levels, 1)
    check("band count", levels.count == bandCount, "\(levels.count)")
    check(
        "low tone lands left of high tone", leftBand < rightBand,
        "200 Hz at band \(leftBand), 4 kHz at band \(rightBand)")
    check(
        "channels stay independent", abs(leftBand - rightBand) > 20,
        "separation \(abs(leftBand - rightBand)) bands")
}

do {
    let harness = Harness()
    let steady = tone(1000, 0.6)
    let generator = { (index: Int) in (steady(index), steady(index)) }
    let first = harness.settle(40, windowSize, generator)

    var drift = 0
    var motion: Float = 0
    for _ in 0..<20 {
        harness.write(windowSize / 3, generator)
        guard let next = harness.snapshot() else { continue }
        drift = max(drift, abs(peakBand(next, 0) - peakBand(first, 0)))
        motion = max(motion, zip(first, next).map { abs($0.x - $1.x) }.max() ?? 0)
    }

    check("steady tone holds its band", drift == 0, "moved \(drift) bands")
    check(
        "steady tone holds its level", motion < 0.02, String(format: "%.4f", motion))
}

do {
    let harness = Harness()
    let quiet = tone(1000, 0.05)
    let loud = tone(1000, 0.9)

    let quietLevels = harness.settle(40, windowSize) { index in (quiet(index), quiet(index)) }
    let quietPeak = quietLevels.map(\.x).max() ?? 0
    let loudLevels = harness.settle(40, windowSize) { index in (loud(index), loud(index)) }
    let loudPeak = loudLevels.map(\.x).max() ?? 0

    check(
        "louder input reads higher", loudPeak > quietPeak + 0.1,
        String(format: "%.3f vs %.3f", loudPeak, quietPeak))
    check("levels stay normalized", loudPeak <= 1.0, String(format: "%.3f", loudPeak))
}

do {
    let harness = Harness()
    let loud = tone(1000, 0.9)
    _ = harness.settle(40, windowSize) { index in (loud(index), loud(index)) }
    let decayed = harness.settle(60, windowSize) { _ in (0, 0) }

    check(
        "silence decays toward zero", (decayed.map(\.x).max() ?? 1) < 0.02,
        String(format: "%.4f", decayed.map(\.x).max() ?? 1))
}

func spread(_ levels: [SIMD4<Float>], _ channel: Int) -> Int {
    let ceiling = levels.map { $0[channel] }.max() ?? 0
    guard ceiling > 0 else { return 0 }
    return levels.filter { $0[channel] > ceiling * 0.2 }.count
}

do {
    let steady = tone(1000, 0.7)
    let generator = { (index: Int) in (steady(index), steady(index)) }

    let sharp = Harness()
    sharp.analyzer.smoothing = 0
    let sharpLevels = sharp.settle(40, windowSize, generator)

    let soft = Harness()
    soft.analyzer.smoothing = 1
    let softLevels = soft.settle(40, windowSize, generator)

    let sharpWidth = spread(sharpLevels, 0)
    let softWidth = spread(softLevels, 0)
    check(
        "smoothing widens a tone across bands", softWidth > sharpWidth * 2,
        "\(sharpWidth) bands at 0%, \(softWidth) at 100%")

    var sharpStep: Float = 0
    var softStep: Float = 0
    for index in 1..<bandCount {
        sharpStep = max(sharpStep, abs(sharpLevels[index].x - sharpLevels[index - 1].x))
        softStep = max(softStep, abs(softLevels[index].x - softLevels[index - 1].x))
    }
    check(
        "smoothing removes band-to-band steps", softStep < sharpStep * 0.6,
        String(format: "step %.3f at 0%%, %.3f at 100%%", sharpStep, softStep))
}

do {
    let harness = Harness()
    let loud = tone(1000, 0.8)
    let levels = harness.settle(40, windowSize) { index in (loud(index), loud(index)) }
    check(
        "peak cap sits at or above the level",
        levels.allSatisfy { $0.z >= $0.x - 0.001 })

    let quiet = harness.settle(3, windowSize) { _ in (0, 0) }
    let held = zip(levels, quiet).contains { $1.z > $0.x * 0.5 }
    check("peak cap lingers after the level drops", held)
}

do {
    let width = 416
    var jagged = [Float](repeating: 0, count: width)
    for index in 0..<width {
        jagged[index] = index % 2 == 0 ? 0.05 : 0.22
    }
    var flat = [Float](repeating: 0, count: width)
    var sharp = [Float](repeating: 0, count: width)
    var soft = [Float](repeating: 0, count: width)

    let sharpKernel = EnvelopeSmoother(smoothing: 0, width: width)
    let softKernel = EnvelopeSmoother(smoothing: 1, width: width)
    check(
        "ocean smoothing widens the kernel", softKernel.radius > sharpKernel.radius * 4,
        "radius \(sharpKernel.radius) at 0%, \(softKernel.radius) at 100%")

    sharpKernel.smooth(jagged, startIndex: 0, gain: 1, into: &sharp)
    softKernel.smooth(jagged, startIndex: 0, gain: 1, into: &soft)

    var sharpStep: Float = 0
    var softStep: Float = 0
    for index in 1..<width {
        sharpStep = max(sharpStep, abs(sharp[index] - sharp[index - 1]))
        softStep = max(softStep, abs(soft[index] - soft[index - 1]))
    }
    check(
        "ocean smoothing flattens column-to-column steps", softStep < sharpStep * 0.1,
        String(format: "step %.4f at 0%%, %.4f at 100%%", sharpStep, softStep))

    let level = [Float](repeating: 0.4, count: width)
    softKernel.smooth(level, startIndex: 0, gain: 1, into: &flat)
    check(
        "ocean smoothing preserves a steady level",
        flat.allSatisfy { abs($0 - 0.4) < 0.001 },
        String(format: "%.4f", flat[width / 2]))
}

do {
    func riseAfter(_ seconds: Double, fps: Double) -> Float {
        let harness = Harness()
        harness.frameInterval = Float(1 / fps)
        let hop = Int(sampleRate / fps)
        let loud = tone(1000, 0.8)

        _ = harness.settle(4, windowSize) { _ in (0, 0) }
        var levels: [SIMD4<Float>] = []
        for _ in 0..<Int(seconds * fps) {
            harness.write(hop) { index in (loud(index), loud(index)) }
            if let next = harness.snapshot() { levels = next }
        }
        return levels.isEmpty ? 0 : levels[peakBand(levels, 0)].x
    }

    let fast = riseAfter(0.15, fps: 60)
    let slow = riseAfter(0.15, fps: 30)
    let gap = abs(fast - slow) / max(fast, 0.001)
    check(
        "attack is frame-rate independent", gap < 0.08,
        String(format: "%.3f at 60 fps, %.3f at 30 fps, %.1f%% apart", fast, slow, gap * 100))

    let harness = Harness()
    harness.frameInterval = 1.0 / 60
    let loud = tone(1000, 0.8)
    let peak = harness.settle(60, windowSize / 4) { index in (loud(index), loud(index)) }
    let band = peakBand(peak, 0)
    check(
        "a loud tone is most of the way up within 150 ms", peak[band].x > 0.4,
        String(format: "%.3f", peak[band].x))
}

print("")
if failures == 0 {
    print("all checks passed")
    exit(0)
}
print("\(failures) check(s) failed")
exit(1)
