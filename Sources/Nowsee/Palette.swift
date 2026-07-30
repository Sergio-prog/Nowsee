import Foundation
import simd

struct Palette {
    let name: String
    let stops: [SIMD3<Float>]

    static let all: [Palette] = [.magma, .inferno, .viridis, .classic]

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
