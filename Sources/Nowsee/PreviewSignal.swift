import AppKit
import QuartzCore
import simd

final class PreviewSignal {
    static let shared = PreviewSignal()

    private static let spectrumRate = 94.0
    private static let envelopeRate = 187.5
    private static let maxCatchUp = 0.1

    private weak var host: NSWindow?
    private var link: CADisplayLink?
    private var phase = 0.0
    private var lastEmit: CFTimeInterval = 0
    private var lastRealSignal: CFTimeInterval = 0
    private var columnDebt = 0.0
    private var peaks = [SIMD2<Float>](repeating: .zero, count: AudioEngine.bandCount)
    private var column = [Float](repeating: 0, count: AudioEngine.rowCount)
    private var bands = [SIMD4<Float>](repeating: .zero, count: AudioEngine.bandCount)

    private let quietFor: CFTimeInterval = 1.0

    var isRunning: Bool { link != nil }
    var hasHost: Bool { driver != nil }

    private var driver: NSView? { host?.contentView }

    func noteRealSignal() {
        lastRealSignal = CACurrentMediaTime()
    }

    func attach(to window: NSWindow) {
        host = window
        applySettings()
    }

    func detach() {
        host = nil
        applySettings()
    }

    func applySettings() {
        if driver != nil, NowseeSettings.shared.mockPreview {
            startLink()
        } else {
            stopLink()
        }
    }

    private func startLink() {
        guard link == nil, let driver else { return }
        let link = driver.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        lastEmit = CACurrentMediaTime()
        columnDebt = 0
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        guard now - lastRealSignal > quietFor else {
            lastEmit = now
            columnDebt = 0
            return
        }

        let interval = 1.0 / Double(max(NowseeSettings.shared.previewFrameRate, 1))
        let elapsed = now - lastEmit
        guard elapsed >= interval * 0.9 else { return }
        lastEmit = now
        emit(elapsed: min(elapsed, Self.maxCatchUp))
    }

    private func emit(elapsed: Double) {
        let source = NowseeSettings.shared.visualization.source
        StripRegistry.shared.withPreviewStrips { strips in
            guard !strips.isEmpty else { return }

            if source == .stereoSpectrum {
                phase += elapsed
                fillBands()
                for strip in strips { strip.update(spectrum: bands) }
                return
            }

            let rate = source == .spectrum ? Self.spectrumRate : Self.envelopeRate
            columnDebt = min(columnDebt + elapsed * rate, 64)
            let count = Int(columnDebt)
            guard count > 0 else { return }
            columnDebt -= Double(count)

            let step = elapsed / Double(count)
            for _ in 0..<count {
                phase += step
                if source == .spectrum {
                    fillColumn()
                    for strip in strips { strip.append(column: column) }
                } else {
                    let envelope = mockEnvelope()
                    for strip in strips { strip.append(low: envelope.low, high: envelope.high) }
                }
            }
        }
    }

    private func contour(_ position: Double, _ time: Double) -> Double {
        var level = exp(-pow((position - 0.06) / 0.08, 2)) * (0.60 + 0.40 * sin(time * 3.0))
        level += exp(-pow((position - 0.30) / 0.12, 2)) * (0.45 + 0.35 * sin(time * 1.9 + 1.1))
        level += exp(-pow((position - 0.58) / 0.11, 2)) * (0.30 + 0.30 * sin(time * 2.7 + 2.4))
        level += exp(-pow((position - 0.84) / 0.13, 2)) * (0.22 + 0.20 * sin(time * 4.3 + 0.5))
        return min(1, max(0, level * (1 - position * 0.2)))
    }

    private func fillBands() {
        for band in 0..<AudioEngine.bandCount {
            let position = Double(band) / Double(AudioEngine.bandCount - 1)
            let left = Float(contour(position, phase))
            let right = Float(contour(position, phase + 0.6))
            peaks[band] = simd_max(peaks[band] * 0.94, SIMD2(left, right))
            bands[band] = SIMD4(left, right, peaks[band].x, peaks[band].y)
        }
    }

    private func fillColumn() {
        for row in 0..<AudioEngine.rowCount {
            let position = Double(row) / Double(AudioEngine.rowCount - 1)
            let sparkle = 0.85 + 0.15 * sin(phase * 9 + position * 24)
            column[row] = Float(contour(position, phase) * sparkle)
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
