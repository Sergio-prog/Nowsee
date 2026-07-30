import Foundation
import NowseeCore
import simd

let columnCount = 256
let windowSize = 8192
let triggerSearch = 2048

var failures = 0

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    let mark = passed ? "ok  " : "FAIL"
    print("\(mark) \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !passed { failures += 1 }
}

final class Harness {
    let left = AudioRingBuffer(capacity: 1 << 15)
    let right = AudioRingBuffer(capacity: 1 << 15)
    let analyzer: ScopeAnalyzer
    private var written = 0

    init() {
        analyzer = ScopeAnalyzer(
            left: left, right: right, columnCount: columnCount,
            windowSize: windowSize, triggerSearch: triggerSearch)
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

    func snapshot() -> (bounds: [SIMD4<Float>], trace: [SIMD2<Float>])? {
        var result: (bounds: [SIMD4<Float>], trace: [SIMD2<Float>])?
        analyzer.snapshot { bounds, trace in result = (bounds, trace) }
        return result
    }
}

func peak(_ values: [Float]) -> Float { values.max() ?? 0 }

print("nowsee-check — scope DSP verification\n")

do {
    let harness = Harness()
    harness.write(windowSize) { _ in (0.5, 0.5) }
    check("no emission before a full window", harness.snapshot() == nil)
}

do {
    let harness = Harness()
    harness.write(windowSize + triggerSearch) { index in
        let phase = Float(index) * 2 * .pi / 128
        return (sin(phase) * 0.8, sin(phase) * 0.2)
    }
    guard let result = harness.snapshot() else {
        check("stereo separation", false, "no snapshot")
        exit(1)
    }
    let leftPeak = peak(result.bounds.map { max(abs($0.x), abs($0.y)) })
    let rightPeak = peak(result.bounds.map { max(abs($0.z), abs($0.w)) })
    check("column count", result.bounds.count == columnCount, "\(result.bounds.count)")
    check(
        "left channel amplitude", abs(leftPeak - 0.8) < 0.05,
        String(format: "%.3f expected 0.800", leftPeak))
    check(
        "right channel amplitude", abs(rightPeak - 0.2) < 0.05,
        String(format: "%.3f expected 0.200", rightPeak))
}

do {
    let harness = Harness()
    harness.write(windowSize + triggerSearch) { index in
        let value = sin(Float(index) * 2 * .pi / Float(windowSize)) * 0.6
        return (value, -value)
    }
    guard let result = harness.snapshot() else { exit(1) }
    let tracePeak = peak(result.trace.map { abs($0.x) })
    check(
        "trace follows low frequency shape", tracePeak > 0.3,
        String(format: "peak %.3f", tracePeak))
    check(
        "trace keeps channels independent",
        result.trace.allSatisfy { abs($0.x + $0.y) < 0.01 })
}

do {
    let harness = Harness()
    harness.write(windowSize + triggerSearch) { index in
        let value: Float = index % 2 == 0 ? 0.7 : -0.7
        return (value, value)
    }
    guard let result = harness.snapshot() else { exit(1) }
    let boundsPeak = peak(result.bounds.map { max(abs($0.x), abs($0.y)) })
    let tracePeak = peak(result.trace.map { abs($0.x) })
    check(
        "bounds keep nyquist content", boundsPeak > 0.6, String(format: "%.3f", boundsPeak))
    check(
        "trace averages nyquist content away", tracePeak < 0.05,
        String(format: "%.3f", tracePeak))
}

do {
    let harness = Harness()
    let period = 512
    let tone = { (index: Int) -> (Float, Float) in
        let value = sin(Float(index) * 2 * .pi / Float(period))
        return (value, value)
    }
    harness.write(windowSize + triggerSearch, tone)
    guard let first = harness.snapshot() else { exit(1) }
    harness.write(period / 4, tone)
    guard let shifted = harness.snapshot() else { exit(1) }

    let drift = peak(zip(first.trace, shifted.trace).map { abs($0.x - $1.x) })
    check(
        "trigger holds phase across snapshots", drift < 0.05,
        String(format: "drift %.4f", drift))
}

do {
    let harness = Harness()
    harness.write(windowSize + triggerSearch) { _ in (0, 0) }
    guard let result = harness.snapshot() else { exit(1) }
    check("silence stays flat", result.bounds.allSatisfy { $0 == .zero })
    check("silent trace stays flat", result.trace.allSatisfy { $0 == .zero })
}

print("")
if failures == 0 {
    print("all checks passed")
    exit(0)
}
print("\(failures) check(s) failed")
exit(1)
