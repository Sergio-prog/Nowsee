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
            + "bar=\(live.filter(\.isActive).count)/\(live.count)"
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

    func broadcastPreview(column: [Float]) {
        for strip in strips.allObjects where strip.isPreview {
            strip.append(column: column)
        }
    }

    func broadcastPreview(low: Float, high: Float) {
        for strip in strips.allObjects where strip.isPreview {
            strip.append(low: low, high: high)
        }
    }

    func broadcastPreview(spectrum: [SIMD4<Float>]) {
        for strip in strips.allObjects where strip.isPreview {
            strip.update(spectrum: spectrum)
        }
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
        strip.barCount = Int(settings.equalizerBarCount)
        strip.barGap = Float(settings.equalizerBarGap)
        let rate = strip.isPreview ? min(settings.frameRate, 30) : settings.frameRate
        strip.redrawInterval = 1.0 / Double(rate)
    }
}
