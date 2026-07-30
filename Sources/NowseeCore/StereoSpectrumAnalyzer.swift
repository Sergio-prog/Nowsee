import Accelerate
import Foundation
import simd

public final class StereoSpectrumAnalyzer {
    public let bandCount: Int
    public let windowSize: Int

    private let left: AudioRingBuffer
    private let right: AudioRingBuffer
    private let leftSTFT: STFT
    private let rightSTFT: STFT
    private let map: LogFrequencyMap

    private var leftFrame: UnsafeMutablePointer<Float>
    private var rightFrame: UnsafeMutablePointer<Float>
    private var magnitudes: [Float]
    private var bands: [Float]
    private var levels: [SIMD2<Float>]

    private let floorDB: Float = -85
    private let spanDB: Float = 80
    private let attack: Float = 0.55
    private let release: Float = 0.12

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
        levels = [SIMD2<Float>](repeating: .zero, count: bandCount)
    }

    deinit {
        leftFrame.deinitialize(count: windowSize)
        rightFrame.deinitialize(count: windowSize)
        leftFrame.deallocate()
        rightFrame.deallocate()
    }

    public func snapshot(_ emit: ([SIMD2<Float>]) -> Void) {
        let available = min(left.framesWritten, right.framesWritten)
        guard available >= UInt64(windowSize) else { return }
        guard left.read(into: leftFrame, count: windowSize, endingAt: available),
            right.read(into: rightFrame, count: windowSize, endingAt: available)
        else { return }

        blend(channel: 0, frame: leftFrame, stft: leftSTFT)
        blend(channel: 1, frame: rightFrame, stft: rightSTFT)
        emit(levels)
    }

    private func blend(channel: Int, frame: UnsafeMutablePointer<Float>, stft: STFT) {
        var loudest: Float = 0
        vDSP_maxmgv(frame, 1, &loudest, vDSP_Length(windowSize))

        if loudest < 1e-6 {
            for index in 0..<bandCount {
                levels[index][channel] *= 1 - release
            }
            return
        }

        stft.magnitudesDB(of: frame, into: &magnitudes)
        map.apply(magnitudes, into: &bands)

        for index in 0..<bandCount {
            let level = max(0, min(1, (bands[index] - floorDB) / spanDB))
            let previous = levels[index][channel]
            let rate = level > previous ? attack : release
            levels[index][channel] = previous + (level - previous) * rate
        }
    }
}
