import AppKit
import Foundation

enum Visualization: String, CaseIterable, Identifiable {
    case spectrogram
    case waveform
    case ocean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrogram: return "Spectrogram"
        case .waveform: return "Waveform"
        case .ocean: return "Ocean"
        }
    }

    var usesEnvelope: Bool {
        self != .spectrogram
    }
}

extension Notification.Name {
    static let nowseeSettingsChanged = Notification.Name("sh.nowsee.settingsChanged")
}

@Observable
final class NowseeSettings {
    static let shared = NowseeSettings()

    static let frameRateOptions = [15, 30, 60, 120]

    var visualization: Visualization { didSet { save(visualization.rawValue, "visualization") } }
    var paletteName: String { didSet { save(paletteName, "palette") } }
    var frameRate: Int { didSet { save(frameRate, "frameRate") } }
    var alwaysOnTop: Bool { didSet { save(alwaysOnTop, "alwaysOnTop") } }
    var windowOpacity: Double { didSet { save(windowOpacity, "windowOpacity") } }
    var barWidth: Double { didSet { save(barWidth, "barWidth") } }
    var barFade: Double { didSet { save(barFade, "barFade") } }
    var barOpacity: Double { didSet { save(barOpacity, "barOpacity") } }
    var waveformGain: Double { didSet { save(waveformGain, "waveformGain") } }

    var palette: Palette {
        Palette.all.first { $0.name == paletteName } ?? .magma
    }

    private var isLoading = true

    private init() {
        let defaults = UserDefaults.standard
        visualization =
            Visualization(rawValue: defaults.string(forKey: "visualization") ?? "") ?? .spectrogram
        paletteName = defaults.string(forKey: "palette") ?? Palette.magma.name
        let storedRate = defaults.integer(forKey: "frameRate")
        frameRate = Self.frameRateOptions.contains(storedRate) ? storedRate : 30
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? false
        windowOpacity = defaults.object(forKey: "windowOpacity") as? Double ?? 1.0
        barWidth = defaults.object(forKey: "barWidth") as? Double ?? 72
        barFade = defaults.object(forKey: "barFade") as? Double ?? 6
        barOpacity = defaults.object(forKey: "barOpacity") as? Double ?? 1.0
        waveformGain = defaults.object(forKey: "waveformGain") as? Double ?? 4.0
        isLoading = false
    }

    private func save(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .nowseeSettingsChanged, object: nil)
    }
}
