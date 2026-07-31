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
    case bars
    case stereo
    case morph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectrogram: return "Spectrogram"
        case .waveform: return "Waveform"
        case .ocean: return "Ocean"
        case .bars: return "Bars"
        case .stereo: return "Stereo"
        case .morph: return "Morph"
        }
    }

    var detail: String {
        switch self {
        case .spectrogram: return "Scrolling frequency map, auto-contrasted."
        case .waveform: return "Scrolling amplitude envelope around a centre line."
        case .ocean: return "Scrolling swell that rises from the bottom edge."
        case .bars:
            return "Classic equalizer — bars rising from the bottom with falling peak caps."
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
        case .bars, .stereo, .morph: return .stereoSpectrum
        }
    }

    var baselineAtBottom: Bool {
        switch self {
        case .spectrogram, .ocean, .bars: return true
        case .waveform, .stereo, .morph: return false
        }
    }

    var usesSmoothing: Bool {
        source == .stereoSpectrum || self == .ocean
    }

    var usesGain: Bool {
        source != .spectrum
    }
}

enum StandbyAnimation: String, CaseIterable, Identifiable {
    case off
    case breathe
    case wave
    case sweep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .breathe: return "Breathe"
        case .wave: return "Wave"
        case .sweep: return "Sweep"
        }
    }

    var detail: String {
        switch self {
        case .off: return "The baseline holds still, and the window stops rendering entirely."
        case .breathe: return "The baseline fades slowly in and out."
        case .wave: return "A slow swell travels along the baseline."
        case .sweep: return "A soft highlight drifts from one end to the other."
        }
    }

    var animates: Bool { self != .off }

    var redrawsPerFrame: Bool { self == .wave || self == .sweep }
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
    var smoothing: Double { didSet { save(smoothing, "smoothing") } }
    var equalizerBarCount: Double { didSet { save(equalizerBarCount, "equalizerBarCount") } }
    var equalizerBarGap: Double { didSet { save(equalizerBarGap, "equalizerBarGap") } }
    var mockPreview: Bool { didSet { save(mockPreview, "mockPreview") } }
    var standby: StandbyAnimation { didSet { save(standby.rawValue, "standby") } }
    var standbyIntensity: Double { didSet { save(standbyIntensity, "standbyIntensity") } }
    var baselineMatchesSystem: Bool { didSet { save(baselineMatchesSystem, "baselineMatchesSystem") } }
    var baselineColor: SIMD3<Float> { didSet { saveColor(baselineColor, "baselineColor") } }
    var baselineOpacity: Double { didSet { save(baselineOpacity, "baselineOpacity") } }
    var customLow: SIMD3<Float> { didSet { saveColor(customLow, "customLow") } }
    var customMid: SIMD3<Float> { didSet { saveColor(customMid, "customMid") } }
    var customHigh: SIMD3<Float> { didSet { saveColor(customHigh, "customHigh") } }

    var baselineNSColor: NSColor {
        NSColor(
            srgbRed: CGFloat(baselineColor.x), green: CGFloat(baselineColor.y),
            blue: CGFloat(baselineColor.z), alpha: 1)
    }

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
        smoothing = defaults.object(forKey: "smoothing") as? Double ?? 0.55
        equalizerBarCount = defaults.object(forKey: "equalizerBarCount") as? Double ?? 56
        equalizerBarGap = defaults.object(forKey: "equalizerBarGap") as? Double ?? 0.16
        mockPreview = defaults.object(forKey: "mockPreview") as? Bool ?? true
        standby = StandbyAnimation(rawValue: defaults.string(forKey: "standby") ?? "") ?? .breathe
        standbyIntensity = defaults.object(forKey: "standbyIntensity") as? Double ?? 0.6
        baselineMatchesSystem = defaults.object(forKey: "baselineMatchesSystem") as? Bool ?? true
        baselineColor = Self.loadColor("baselineColor", defaults) ?? SIMD3(1, 1, 1)
        baselineOpacity = defaults.object(forKey: "baselineOpacity") as? Double ?? 1.0
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
