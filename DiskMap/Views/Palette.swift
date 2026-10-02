import SwiftUI

/// Treemap colours. Eight hues in a fixed order, then grey for everything else.
/// Light and dark mode each get their own tuned set.
struct Palette {
    let series: [Color]
    let other: Color
    let surface: Color
    let ink: Color

    static let light = Palette(
        hex: ["2a78d6", "eb6834", "1baf7a", "eda100", "e87ba4", "008300", "4a3aa7", "e34948"],
        other: "b5b3ab", surface: "fcfcfb", ink: "0b0b0b")
    static let dark = Palette(
        hex: ["3987e5", "d95926", "199e70", "c98500", "d55181", "008300", "9085e9", "e66767"],
        other: "5c5b57", surface: "1a1a19", ink: "ffffff")

    static func current(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    private let seriesRGB: [SIMD3<Double>]
    private let otherRGB: SIMD3<Double>
    private let surfaceRGB: SIMD3<Double>

    private init(hex: [String], other: String, surface: String, ink: String) {
        seriesRGB = hex.map(Self.rgb)
        otherRGB = Self.rgb(other)
        surfaceRGB = Self.rgb(surface)
        series = seriesRGB.map(Self.color)
        self.other = Self.color(otherRGB)
        self.surface = Self.color(surfaceRGB)
        self.ink = Self.color(Self.rgb(ink))
    }

    /// The colour for a group, blended toward the background the deeper the tile sits.
    func fill(group: Int, depth: Int, placeholder: Bool) -> Color {
        let base = placeholder || group >= seriesRGB.count ? otherRGB : seriesRGB[group]
        let amount = placeholder ? 0.45 : min(0.12 + Double(depth) * 0.14, 0.7)
        return Self.color(base + (surfaceRGB - base) * amount)
    }

    func swatch(group: Int) -> Color { group < series.count ? series[group] : other }

    private static func rgb(_ hex: String) -> SIMD3<Double> {
        let v = UInt32(hex, radix: 16) ?? 0
        return SIMD3(Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff)) / 255
    }

    private static func color(_ c: SIMD3<Double>) -> Color { Color(red: c.x, green: c.y, blue: c.z) }
}
