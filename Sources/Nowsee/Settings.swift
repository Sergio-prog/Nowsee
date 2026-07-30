import Foundation

enum Settings {
    static let frameRateOptions = [15, 30, 60, 120]
    static let menuBarCeiling = 20

    private enum Key {
        static let frameRate = "frameRate"
        static let palette = "palette"
    }

    static var frameRate: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Key.frameRate)
            return frameRateOptions.contains(stored) ? stored : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.frameRate) }
    }

    static var paletteName: String {
        get { UserDefaults.standard.string(forKey: Key.palette) ?? Palette.magma.name }
        set { UserDefaults.standard.set(newValue, forKey: Key.palette) }
    }

    static var palette: Palette {
        Palette.all.first { $0.name == paletteName } ?? .magma
    }
}
