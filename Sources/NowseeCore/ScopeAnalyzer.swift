import Foundation
import simd

public final class ScopeAnalyzer {
    public let columnCount: Int
    public let windowSize: Int
    public let triggerSearch: Int

    private let left: AudioRingBuffer
    private let right: AudioRingBuffer
    private let span: Int
    private var leftFrame: UnsafeMutablePointer<Float>
    private var rightFrame: UnsafeMutablePointer<Float>
    private var bounds: [SIMD4<Float>]
    private var trace: [SIMD2<Float>]

    public init(
        left: AudioRingBuffer,
        right: AudioRingBuffer,
        columnCount: Int = 256,
        windowSize: Int = 8192,
        triggerSearch: Int = 2048
    ) {
        self.left = left
        self.right = right
        self.columnCount = columnCount
        self.windowSize = windowSize
        self.triggerSearch = triggerSearch
        span = windowSize + triggerSearch
        leftFrame = .allocate(capacity: span)
        rightFrame = .allocate(capacity: span)
        leftFrame.initialize(repeating: 0, count: span)
        rightFrame.initialize(repeating: 0, count: span)
        bounds = [SIMD4<Float>](repeating: .zero, count: columnCount)
        trace = [SIMD2<Float>](repeating: .zero, count: columnCount)
    }

    deinit {
        leftFrame.deinitialize(count: span)
        rightFrame.deinitialize(count: span)
        leftFrame.deallocate()
        rightFrame.deallocate()
    }

    public func snapshot(_ emit: ([SIMD4<Float>], [SIMD2<Float>]) -> Void) {
        let available = min(left.framesWritten, right.framesWritten)
        guard available >= UInt64(span) else { return }
        guard left.read(into: leftFrame, count: span, endingAt: available),
            right.read(into: rightFrame, count: span, endingAt: available)
        else { return }

        measure(from: triggerOffset())
        emit(bounds, trace)
    }

    private func triggerOffset() -> Int {
        let threshold: Float = 0.005
        var armed = false
        for index in 0..<triggerSearch {
            let sample = leftFrame[index]
            if sample < -threshold {
                armed = true
            } else if armed, sample > threshold {
                return index
            }
        }
        return 0
    }

    private func measure(from start: Int) {
        let slice = windowSize / columnCount
        let scale = 1 / Float(slice)

        for column in 0..<columnCount {
            let base = start + column * slice
            var lowest = SIMD2<Float>.zero
            var highest = SIMD2<Float>.zero
            var sum = SIMD2<Float>.zero

            for offset in base..<(base + slice) {
                let pair = SIMD2(leftFrame[offset], rightFrame[offset])
                lowest = simd_min(lowest, pair)
                highest = simd_max(highest, pair)
                sum += pair
            }

            bounds[column] = SIMD4(lowest.x, highest.x, lowest.y, highest.y)
            trace[column] = sum * scale
        }
    }
}
