import Accelerate
import Foundation

public final class SpectrumAnalyzer {
    public let rowCount: Int
    public let hopSize: Int
    public let windowSize: Int

    private let ring: AudioRingBuffer
    private let stft: STFT
    private let map: LogFrequencyMap
    private let contrast = AutoContrast()

    private var frame: UnsafeMutablePointer<Float>
    private var magnitudes: [Float]
    private var rows: [Float]
    private var normalized: [Float]
    private var nextHopEnd: UInt64 = 0

    public var contrastRange: (low: Float, high: Float) { (contrast.lowDB, contrast.highDB) }

    public init(
        ring: AudioRingBuffer,
        sampleRate: Double,
        windowSize: Int = 2048,
        hopSize: Int = 512,
        rowCount: Int = 256
    ) {
        self.ring = ring
        self.windowSize = windowSize
        self.hopSize = hopSize
        self.rowCount = rowCount
        stft = STFT(windowSize: windowSize)
        map = LogFrequencyMap(
            binCount: stft.binCount,
            sampleRate: sampleRate,
            rowCount: rowCount
        )
        frame = .allocate(capacity: windowSize)
        frame.initialize(repeating: 0, count: windowSize)
        magnitudes = [Float](repeating: 0, count: stft.binCount)
        rows = [Float](repeating: 0, count: rowCount)
        normalized = [Float](repeating: 0, count: rowCount)
    }

    deinit {
        frame.deinitialize(count: windowSize)
        frame.deallocate()
    }

    public func drainColumns(_ emit: ([Float]) -> Void) {
        let available = ring.framesWritten
        if nextHopEnd < UInt64(windowSize) {
            nextHopEnd = UInt64(windowSize)
        }
        if available > nextHopEnd, available - nextHopEnd > UInt64(1 << 16) {
            nextHopEnd = available
        }

        while available >= nextHopEnd {
            guard ring.read(into: frame, count: windowSize, endingAt: nextHopEnd) else { break }

            var loudest: Float = 0
            vDSP_maxmgv(frame, 1, &loudest, vDSP_Length(windowSize))
            if loudest < 1e-6 {
                for index in normalized.indices { normalized[index] = 0 }
                emit(normalized)
                nextHopEnd += UInt64(hopSize)
                continue
            }

            stft.magnitudesDB(of: frame, into: &magnitudes)
            map.apply(magnitudes, into: &rows)
            contrast.update(rows)
            contrast.normalize(rows, into: &normalized)
            emit(normalized)
            nextHopEnd += UInt64(hopSize)
        }
    }
}
