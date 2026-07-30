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

    func snapshot() -> [SIMD4<Float>]? {
        var result: [SIMD4<Float>]?
        analyzer.snapshot { levels in result = levels }
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

print("")
if failures == 0 {
    print("all checks passed")
    exit(0)
}
print("\(failures) check(s) failed")
exit(1)
