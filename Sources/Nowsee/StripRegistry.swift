import AppKit
import simd

final class StripRegistry {
    static let shared = StripRegistry()

    private let strips = NSHashTable<StripVisualizationView>.weakObjects()

    var registeredCount: Int { strips.allObjects.count }

    var activitySummary: String {
        let all = strips.allObjects
        let previews = all.filter(\.isPreview)
        let live = all.filter { !$0.isPreview }
        return "preview=\(previews.filter(\.isActive).count)/\(previews.count) "
            + "previewDraws=\(previews.reduce(0) { $0 + $1.drawsCompleted }) "
            + "bar=\(live.filter(\.isActive).count)/\(live.count) "
            + "barDraws=\(live.reduce(0) { $0 + $1.drawsCompleted })"
    }

    func register(_ strip: StripVisualizationView) {
        strips.add(strip)
        applyCurrentSettings(to: strip)
    }

    func broadcast(column: [Float]) {
        if (column.max() ?? 0) > 0.2 { PreviewSignal.shared.noteRealSignal() }
        for strip in strips.allObjects {
            strip.append(column: column)
        }
    }

    func broadcast(low: Float, high: Float) {
        if max(abs(low), abs(high)) > 0.002 { PreviewSignal.shared.noteRealSignal() }
        for strip in strips.allObjects {
            strip.append(low: low, high: high)
        }
    }

    func broadcast(spectrum: [SIMD4<Float>]) {
        let peak = spectrum.reduce(Float(0)) { max($0, max($1.x, $1.y)) }
        if peak > 0.01 { PreviewSignal.shared.noteRealSignal() }
        for strip in strips.allObjects {
            strip.update(spectrum: spectrum)
        }
    }

    func withPreviewStrips(_ body: ([StripVisualizationView]) -> Void) {
        body(strips.allObjects.filter(\.isPreview))
    }

    func setPaused(_ paused: Bool) {
        for strip in strips.allObjects {
            strip.setPaused(paused)
        }
    }

    func applySettings() {
        for strip in strips.allObjects {
            applyCurrentSettings(to: strip)
        }
    }

    private func applyCurrentSettings(to strip: StripVisualizationView) {
        let settings = NowseeSettings.shared
        strip.mode = settings.visualization
        strip.apply(palette: settings.palette)
        strip.gain = Float(settings.waveformGain)
        strip.smoothing = Float(settings.smoothing)
        strip.barCount = Int(settings.equalizerBarCount)
        strip.barGap = Float(settings.equalizerBarGap)
        strip.standby = settings.standby
        strip.standbyIntensity = CGFloat(settings.standbyIntensity)
        strip.baselineOpacity = CGFloat(settings.baselineOpacity)
        strip.baselineTint = settings.baselineMatchesSystem ? nil : settings.baselineNSColor
        let rate = strip.isPreview ? settings.previewFrameRate : settings.menuBarFrameRate
        strip.redrawInterval = 1.0 / Double(max(1, rate))
    }
}
