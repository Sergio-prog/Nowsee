import AppKit
import Foundation

enum SignalSource {
    case spectrum
    case envelope
    case stereoSpectrum
}

enum Visualization: String, CaseIterable, Identifiable {
    case spectrogram
    case waveform
    case ocean
    case stereo
    case morph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrogram: return "Spectrogram"
        case .waveform: return "Waveform"
        case .ocean: return "Ocean"
        case .stereo: return "Stereo"
        case .morph: return "Morph"
        }
    }

    var detail: String {
        switch self {
        case .spectrogram: return "Scrolling frequency map, auto-contrasted."
        case .waveform: return "Scrolling amplitude envelope around a centre line."
        case .ocean: return "Scrolling swell that rises from the bottom edge."
        case .stereo:
            return "Bass left, treble right. Left channel above the axis, right below."
        case .morph:
            return "Bass left, treble right. One morphing line per channel."
        }
    }

    var source: SignalSource {
        switch self {
        case .spectrogram: return .spectrum
        case .waveform, .ocean: return .envelope
        case .stereo, .morph: return .stereoSpectrum
        }
    }

    var usesGain: Bool {
        source != .spectrum
    }
}

extension Notification.Name {
    static let nowseeSettingsChanged = Notification.Name("sh.nowsee.settingsChanged")
}

@Observable
final class NowseeSettings {
    static let shared = NowseeSettings()

    static var displayRefreshRate: Int {
        max(30, NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
    }

    static var frameRateOptions: [Int] {
        [15, 30, 60, 120].filter { $0 <= displayRefreshRate }
    }

    var visualization: Visualization { didSet { save(visualization.rawValue, "visualization") } }
    var paletteName: String { didSet { save(paletteName, "palette") } }
    var frameRate: Int { didSet { save(frameRate, "frameRate") } }
    var alwaysOnTop: Bool { didSet { save(alwaysOnTop, "alwaysOnTop") } }
    var windowOpacity: Double { didSet { save(windowOpacity, "windowOpacity") } }
    var barWidth: Double { didSet { save(barWidth, "barWidth") } }
    var barFade: Double { didSet { save(barFade, "barFade") } }
    var barOpacity: Double { didSet { save(barOpacity, "barOpacity") } }
    var waveformGain: Double { didSet { save(waveformGain, "waveformGain") } }
    var customLow: SIMD3<Float> { didSet { saveColor(customLow, "customLow") } }
    var customMid: SIMD3<Float> { didSet { saveColor(customMid, "customMid") } }
    var customHigh: SIMD3<Float> { didSet { saveColor(customHigh, "customHigh") } }

    var customPalette: Palette {
        .custom(low: customLow, mid: customMid, high: customHigh)
    }

    var palette: Palette {
        if paletteName == Palette.customName { return customPalette }
        return Palette.builtIn.first { $0.name == paletteName } ?? .magma
    }

    private var isLoading = true

    private init() {
        let defaults = UserDefaults.standard
        visualization =
            Visualization(rawValue: defaults.string(forKey: "visualization") ?? "") ?? .spectrogram
        paletteName = defaults.string(forKey: "palette") ?? Palette.magma.name
        let storedRate = defaults.integer(forKey: "frameRate")
        frameRate = Self.frameRateOptions.contains(storedRate) ? storedRate : 30
        customLow = Self.loadColor("customLow", defaults) ?? SIMD3(0.043, 0.055, 0.310)
        customMid = Self.loadColor("customMid", defaults) ?? SIMD3(0.180, 0.800, 0.451)
        customHigh = Self.loadColor("customHigh", defaults) ?? SIMD3(0.976, 0.980, 0.945)
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

    private func saveColor(_ color: SIMD3<Float>, _ key: String) {
        save([color.x, color.y, color.z], key)
    }

    private static func loadColor(_ key: String, _ defaults: UserDefaults) -> SIMD3<Float>? {
        guard let stored = defaults.array(forKey: key) as? [Double], stored.count == 3 else {
            return nil
        }
        return SIMD3(Float(stored[0]), Float(stored[1]), Float(stored[2]))
    }
}
