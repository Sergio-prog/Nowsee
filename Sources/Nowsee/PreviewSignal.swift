import Foundation
import QuartzCore
import simd

final class PreviewSignal {
    static let shared = PreviewSignal()

    private var timer: Timer?
    private var phase = 0.0
    private var lastRealSignal: CFTimeInterval = 0
    private var peaks = [SIMD2<Float>](repeating: .zero, count: AudioEngine.bandCount)

    private let quietFor: CFTimeInterval = 1.0

    func noteRealSignal() {
        lastRealSignal = CACurrentMediaTime()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard CACurrentMediaTime() - lastRealSignal > quietFor else { return }

        switch NowseeSettings.shared.visualization.source {
        case .spectrum:
            for _ in 0..<3 {
                phase += 0.011
                StripRegistry.shared.broadcastPreview(column: mockColumn())
            }
        case .envelope:
            for _ in 0..<6 {
                phase += 0.005
                let envelope = mockEnvelope()
                StripRegistry.shared.broadcastPreview(low: envelope.low, high: envelope.high)
            }
        case .stereoSpectrum:
            phase += 1.0 / 30
            StripRegistry.shared.broadcastPreview(spectrum: mockBands())
        }
    }

    private func contour(_ position: Double, _ time: Double) -> Double {
        var level = exp(-pow((position - 0.06) / 0.08, 2)) * (0.60 + 0.40 * sin(time * 3.0))
        level += exp(-pow((position - 0.30) / 0.12, 2)) * (0.45 + 0.35 * sin(time * 1.9 + 1.1))
        level += exp(-pow((position - 0.58) / 0.11, 2)) * (0.30 + 0.30 * sin(time * 2.7 + 2.4))
        level += exp(-pow((position - 0.84) / 0.13, 2)) * (0.22 + 0.20 * sin(time * 4.3 + 0.5))
        return min(1, max(0, level * (1 - position * 0.2)))
    }

    private func mockBands() -> [SIMD4<Float>] {
        var result = [SIMD4<Float>](repeating: .zero, count: AudioEngine.bandCount)
        for band in 0..<AudioEngine.bandCount {
            let position = Double(band) / Double(AudioEngine.bandCount - 1)
            let left = Float(contour(position, phase))
            let right = Float(contour(position, phase + 0.6))
            peaks[band] = simd_max(peaks[band] * 0.94, SIMD2(left, right))
            result[band] = SIMD4(left, right, peaks[band].x, peaks[band].y)
        }
        return result
    }

    private func mockColumn() -> [Float] {
        (0..<AudioEngine.rowCount).map { row in
            let position = Double(row) / Double(AudioEngine.rowCount - 1)
            let sparkle = 0.85 + 0.15 * sin(phase * 9 + position * 24)
            return Float(contour(position, phase) * sparkle)
        }
    }

    private func mockEnvelope() -> (low: Float, high: Float) {
        let swell = 0.10 + 0.085 * sin(phase * 2.2) * sin(phase * 0.73)
        let wobble = sin(phase * 57) * 0.55 + sin(phase * 93 + 1.2) * 0.3
        let upper = Float(swell * (1 + wobble))
        let lower = Float(swell * (1 + sin(phase * 61 + 2.1) * 0.5))
        return (low: -abs(lower), high: abs(upper))
    }
}
