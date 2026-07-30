import AppKit

final class StripRegistry {
    static let shared = StripRegistry()

    private let strips = NSHashTable<StripVisualizationView>.weakObjects()

    func register(_ strip: StripVisualizationView) {
        strips.add(strip)
        applyCurrentSettings(to: strip)
    }

    func broadcast(column: [Float]) {
        for strip in strips.allObjects {
            strip.append(column: column)
        }
    }

    func broadcast(low: Float, high: Float) {
        for strip in strips.allObjects {
            strip.append(low: low, high: high)
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
        strip.redrawInterval = 1.0 / Double(min(settings.frameRate, 20))
    }
}
