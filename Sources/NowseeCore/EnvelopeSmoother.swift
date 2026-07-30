import Foundation

public struct EnvelopeSmoother {
    public static let sigmaScale: Float = 0.018
    public static let maxRadius = 36

    public let radius: Int
    public let weights: [Float]

    private let normalization: Float

    public static func sigma(smoothing: Float, width: Int) -> Float {
        0.6 + max(0, smoothing) * Float(width) * sigmaScale
    }

    public init(smoothing: Float, width: Int) {
        let sigma = Self.sigma(smoothing: smoothing, width: width)
        radius = max(1, min(Self.maxRadius, Int((sigma * 2).rounded(.up))))

        let spread = 1 / (2 * sigma * sigma)
        var kernel = [Float](repeating: 0, count: radius * 2 + 1)
        var total: Float = 0
        for tap in -radius...radius {
            let weight = exp(-Float(tap * tap) * spread)
            kernel[tap + radius] = weight
            total += weight
        }
        weights = kernel
        normalization = 1 / total
    }

    public func smooth(
        _ magnitudes: [Float], startIndex: Int, gain: Float, into output: inout [Float]
    ) {
        let width = magnitudes.count
        guard width > 0, output.count == width else { return }

        for column in 0..<width {
            var total: Float = 0
            for tap in -radius...radius {
                let index = (startIndex + column + tap) % width
                total += magnitudes[index < 0 ? index + width : index] * weights[tap + radius]
            }
            output[column] = min(1, total * normalization * gain)
        }
    }
}
