import Accelerate
import Foundation

public final class WaveformAnalyzer {
    public let hopSize: Int

    private let ring: AudioRingBuffer
    private var frame: UnsafeMutablePointer<Float>
    private var nextHopEnd: UInt64 = 0

    public init(ring: AudioRingBuffer, hopSize: Int = 512) {
        self.ring = ring
        self.hopSize = hopSize
        frame = .allocate(capacity: hopSize)
        frame.initialize(repeating: 0, count: hopSize)
    }

    deinit {
        frame.deinitialize(count: hopSize)
        frame.deallocate()
    }

    public func drainEnvelopes(_ emit: (Float, Float) -> Void) {
        let available = ring.framesWritten
        if nextHopEnd < UInt64(hopSize) {
            nextHopEnd = UInt64(hopSize)
        }
        if available > nextHopEnd, available - nextHopEnd > UInt64(1 << 16) {
            nextHopEnd = available
        }

        while available >= nextHopEnd {
            guard ring.read(into: frame, count: hopSize, endingAt: nextHopEnd) else { break }
            var lowest: Float = 0
            var highest: Float = 0
            vDSP_minv(frame, 1, &lowest, vDSP_Length(hopSize))
            vDSP_maxv(frame, 1, &highest, vDSP_Length(hopSize))
            emit(lowest, highest)
            nextHopEnd += UInt64(hopSize)
        }
    }
}
