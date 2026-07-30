import Foundation
import simd

struct Palette: Equatable {
    let name: String
    let stops: [SIMD3<Float>]

    static let customName = "Custom"

    static let builtIn: [Palette] = [
        .magma, .inferno, .viridis, .classic, .mono, .ice, .sunset, .neon, .ember,
    ]

    static var all: [Palette] { builtIn + [NowseeSettings.shared.customPalette] }

    static let magma = Palette(
        name: "Magma",
        stops: [
            SIMD3(0.001, 0.000, 0.014),
            SIMD3(0.232, 0.059, 0.437),
            SIMD3(0.550, 0.161, 0.506),
            SIMD3(0.868, 0.288, 0.409),
            SIMD3(0.988, 0.553, 0.383),
            SIMD3(0.987, 0.991, 0.750),
        ])

    static let inferno = Palette(
        name: "Inferno",
        stops: [
            SIMD3(0.001, 0.000, 0.014),
            SIMD3(0.258, 0.039, 0.406),
            SIMD3(0.578, 0.148, 0.404),
            SIMD3(0.865, 0.317, 0.226),
            SIMD3(0.978, 0.557, 0.035),
            SIMD3(0.988, 0.998, 0.645),
        ])

    static let viridis = Palette(
        name: "Viridis",
        stops: [
            SIMD3(0.267, 0.005, 0.329),
            SIMD3(0.283, 0.141, 0.458),
            SIMD3(0.229, 0.322, 0.545),
            SIMD3(0.127, 0.567, 0.551),
            SIMD3(0.369, 0.789, 0.383),
            SIMD3(0.993, 0.906, 0.144),
        ])

    static let classic = Palette(
        name: "Classic",
        stops: [
            SIMD3(0.000, 0.000, 0.000),
            SIMD3(0.043, 0.055, 0.310),
            SIMD3(0.000, 0.482, 0.702),
            SIMD3(0.180, 0.800, 0.451),
            SIMD3(0.965, 0.878, 0.204),
            SIMD3(0.976, 0.980, 0.945),
        ])

    static let mono = Palette(
        name: "Mono",
        stops: [
            SIMD3(0.000, 0.000, 0.000),
            SIMD3(0.180, 0.180, 0.180),
            SIMD3(0.450, 0.450, 0.450),
            SIMD3(0.720, 0.720, 0.720),
            SIMD3(0.910, 0.910, 0.910),
            SIMD3(1.000, 1.000, 1.000),
        ])

    static let ice = Palette(
        name: "Ice",
        stops: [
            SIMD3(0.008, 0.020, 0.090),
            SIMD3(0.031, 0.145, 0.325),
            SIMD3(0.055, 0.361, 0.588),
            SIMD3(0.184, 0.616, 0.808),
            SIMD3(0.545, 0.855, 0.925),
            SIMD3(0.925, 0.988, 1.000),
        ])

    static let sunset = Palette(
        name: "Sunset",
        stops: [
            SIMD3(0.047, 0.020, 0.106),
            SIMD3(0.267, 0.063, 0.294),
            SIMD3(0.588, 0.129, 0.353),
            SIMD3(0.867, 0.318, 0.271),
            SIMD3(0.976, 0.612, 0.259),
            SIMD3(1.000, 0.918, 0.686),
        ])

    static let neon = Palette(
        name: "Neon",
        stops: [
            SIMD3(0.020, 0.008, 0.055),
            SIMD3(0.180, 0.031, 0.400),
            SIMD3(0.494, 0.055, 0.749),
            SIMD3(0.902, 0.098, 0.647),
            SIMD3(0.298, 0.949, 0.898),
            SIMD3(0.902, 1.000, 0.984),
        ])

    static let ember = Palette(
        name: "Ember",
        stops: [
            SIMD3(0.020, 0.008, 0.004),
            SIMD3(0.243, 0.043, 0.020),
            SIMD3(0.545, 0.129, 0.024),
            SIMD3(0.816, 0.290, 0.031),
            SIMD3(0.965, 0.561, 0.114),
            SIMD3(1.000, 0.898, 0.639),
        ])

    static func custom(low: SIMD3<Float>, mid: SIMD3<Float>, high: SIMD3<Float>) -> Palette {
        Palette(
            name: customName,
            stops: [
                low * 0.15,
                low,
                mix(low, mid, t: 0.5),
                mid,
                mix(mid, high, t: 0.5),
                high,
            ])
    }

    func lookupTable(count: Int = 256) -> [SIMD4<Float>] {
        (0..<count).map { index in
            let position = Float(index) / Float(count - 1) * Float(stops.count - 1)
            let lower = min(Int(position), stops.count - 1)
            let upper = min(lower + 1, stops.count - 1)
            let blend = position - Float(lower)
            let color = mix(stops[lower], stops[upper], t: blend)
            return SIMD4(color.x, color.y, color.z, 1)
        }
    }
}
