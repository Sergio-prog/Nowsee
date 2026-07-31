import Accelerate
import Foundation
import simd

public final class StereoSpectrumAnalyzer {
    public let bandCount: Int
    public let windowSize: Int

    public var smoothing: Float = 0.45 {
        didSet { if smoothing != oldValue { rebuildKernel() } }
    }

    private let left: AudioRingBuffer
    private let right: AudioRingBuffer
    private let leftSTFT: STFT
    private let rightSTFT: STFT
    private let map: LogFrequencyMap

    private var leftFrame: UnsafeMutablePointer<Float>
    private var rightFrame: UnsafeMutablePointer<Float>
    private var magnitudes: [Float]
    private var bands: [Float]
    private var shaped: [Float]
    private var kernel: [Float] = [1]
    private var levels: [SIMD4<Float>]

    private let floorDB: Float = -85
    private let spanDB: Float = 80
    private let peakTau: Float = 0.27

    private var attackTau: Float { 0.020 + smoothing * 0.085 }
    private var releaseTau: Float { 0.110 + smoothing * 0.215 }

    private func rate(_ tau: Float, _ elapsed: Float) -> Float {
        tau <= 0 ? 1 : 1 - exp(-elapsed / tau)
    }

    public init(
        left: AudioRingBuffer,
        right: AudioRingBuffer,
        sampleRate: Double,
        bandCount: Int = 128,
        windowSize: Int = 2048
    ) {
        self.left = left
        self.right = right
        self.bandCount = bandCount
        self.windowSize = windowSize

        leftSTFT = STFT(windowSize: windowSize)
        rightSTFT = STFT(windowSize: windowSize)
        map = LogFrequencyMap(
            binCount: leftSTFT.binCount, sampleRate: sampleRate, rowCount: bandCount)

        leftFrame = .allocate(capacity: windowSize)
        rightFrame = .allocate(capacity: windowSize)
        leftFrame.initialize(repeating: 0, count: windowSize)
        rightFrame.initialize(repeating: 0, count: windowSize)
        magnitudes = [Float](repeating: 0, count: leftSTFT.binCount)
        bands = [Float](repeating: 0, count: bandCount)
        shaped = [Float](repeating: 0, count: bandCount)
        levels = [SIMD4<Float>](repeating: .zero, count: bandCount)
        rebuildKernel()
    }

    deinit {
        leftFrame.deinitialize(count: windowSize)
        rightFrame.deinitialize(count: windowSize)
        leftFrame.deallocate()
        rightFrame.deallocate()
    }

    public func snapshot(elapsed: Float, _ emit: ([SIMD4<Float>]) -> Void) {
        let available = min(left.framesWritten, right.framesWritten)
        guard available >= UInt64(windowSize) else { return }
        guard left.read(into: leftFrame, count: windowSize, endingAt: available),
            right.read(into: rightFrame, count: windowSize, endingAt: available)
        else { return }

        let step = max(0, min(0.25, elapsed))
        blend(channel: 0, frame: leftFrame, stft: leftSTFT, elapsed: step)
        blend(channel: 1, frame: rightFrame, stft: rightSTFT, elapsed: step)
        emit(levels)
    }

    private func rebuildKernel() {
        let radius = Int((smoothing * 12).rounded())
        guard radius > 0 else {
            kernel = [1]
            return
        }
        let sigma = max(0.6, smoothing * 6)
        let weights = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        kernel = weights.map { $0 / total }
    }

    private func blend(
        channel: Int, frame: UnsafeMutablePointer<Float>, stft: STFT, elapsed: Float
    ) {
        let attack = rate(attackTau, elapsed)
        let release = rate(releaseTau, elapsed)
        let peakFall = exp(-elapsed / peakTau)

        var loudest: Float = 0
        vDSP_maxmgv(frame, 1, &loudest, vDSP_Length(windowSize))

        if loudest < 1e-6 {
            for index in 0..<bandCount {
                levels[index][channel] *= 1 - release
                levels[index][channel + 2] *= peakFall
            }
            return
        }

        stft.magnitudesDB(of: frame, into: &magnitudes)
        map.apply(magnitudes, into: &bands)

        for index in 0..<bandCount {
            bands[index] = max(0, min(1, (bands[index] - floorDB) / spanDB))
        }
        spread(bands, into: &shaped)

        for index in 0..<bandCount {
            let target = shaped[index]
            let previous = levels[index][channel]
            let rate = target > previous ? attack : release
            let level = previous + (target - previous) * rate
            levels[index][channel] = level
            levels[index][channel + 2] = max(levels[index][channel + 2] * peakFall, level)
        }
    }

    private func spread(_ source: [Float], into destination: inout [Float]) {
        guard kernel.count > 1 else {
            destination = source
            return
        }
        let radius = kernel.count / 2
        for index in 0..<bandCount {
            var total: Float = 0
            for (offset, weight) in kernel.enumerated() {
                let position = min(bandCount - 1, max(0, index + offset - radius))
                total += source[position] * weight
            }
            destination[index] = total
        }
    }
}
