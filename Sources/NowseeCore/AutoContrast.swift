import Accelerate
import Foundation

public final class AutoContrast {
    private let resolution = 160
    private let floorDB: Float = -140
    private let ceilingDB: Float = 20
    private let decay: Float
    private let lowPercentile: Float
    private let highPercentile: Float
    private let minimumSpanDB: Float = 24
    private let smoothing: Float = 0.12
    private let quietestUsefulDB: Float = -95

    private var histogram: [Float]

    public private(set) var lowDB: Float = -90
    public private(set) var highDB: Float = -20

    public init(decay: Float = 0.985, lowPercentile: Float = 0.05, highPercentile: Float = 0.98) {
        self.decay = decay
        self.lowPercentile = lowPercentile
        self.highPercentile = highPercentile
        histogram = [Float](repeating: 0, count: resolution)
    }

    public func update(_ values: [Float]) {
        vDSP.multiply(decay, histogram, result: &histogram)

        let span = ceilingDB - floorDB
        for value in values where value.isFinite {
            let index = Int((value - floorDB) / span * Float(resolution - 1))
            histogram[max(0, min(resolution - 1, index))] += 1
        }

        let total = vDSP.sum(histogram)
        guard total > 0 else { return }

        var cumulative: Float = 0
        var low = floorDB
        var high = ceilingDB
        var foundLow = false
        for (index, count) in histogram.enumerated() {
            cumulative += count
            let fraction = cumulative / total
            if !foundLow, fraction >= lowPercentile {
                low = decibels(atIndex: index)
                foundLow = true
            }
            if fraction >= highPercentile {
                high = decibels(atIndex: index)
                break
            }
        }

        low = max(low, quietestUsefulDB)
        high = max(high, low + minimumSpanDB)
        lowDB += (low - lowDB) * smoothing
        highDB += (high - highDB) * smoothing
    }

    public func normalize(_ values: [Float], into output: inout [Float]) {
        let span = max(highDB - lowDB, 1)
        for index in values.indices {
            output[index] = max(0, min(1, (values[index] - lowDB) / span))
        }
    }

    private func decibels(atIndex index: Int) -> Float {
        floorDB + (ceilingDB - floorDB) * Float(index) / Float(resolution - 1)
    }
}
