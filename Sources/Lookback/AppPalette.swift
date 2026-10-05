import SwiftUI

/// Stable, visually distinct colours per app name.
///
/// Colours are HSB triples: favourites for daily apps (hues spread wide —
/// Chrome blue vs Code orange can never collide), a 12-hue ring as fallback.
/// Same name → same colour, forever.
///
/// Detail blocks never hash to a colour on their own (two siblings did land
/// on the same blue that way). They take shades of their parent app colour
/// by sibling index — distinct by construction, grouped by family.
enum AppPalette {
    private static let favourites: [String: (Double, Double, Double)] = [
        "Google Chrome": (0.60, 0.70, 0.95),
        "Chrome": (0.60, 0.70, 0.95),
        "Safari": (0.52, 0.70, 0.95),
        "Code": (0.07, 0.80, 0.95),
        "Xcode": (0.48, 0.65, 0.90),
        "Terminal": (0.35, 0.65, 0.85),
        "Slack": (0.78, 0.60, 0.90),
        "Finder": (0.14, 0.75, 0.95),
    ]

    private static let ringHues: [Double] = [
        0.00, 0.07, 0.13, 0.25, 0.35, 0.43,
        0.50, 0.58, 0.66, 0.75, 0.83, 0.92,
    ]

    private static func hsb(for name: String) -> (Double, Double, Double) {
        if let c = favourites[name] { return c }
        var h: UInt64 = 146959
        for b in name.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return (ringHues[Int(h % UInt64(ringHues.count))], 0.65, 0.90)
    }

    static func color(for name: String) -> Color {
        let (h, s, b) = hsb(for: name)
        return Color(hue: h, saturation: s, brightness: b)
    }

    /// Sibling-indexed shade of the parent app colour for a detail block.
    /// Index 0 is the base itself; later siblings step darker/brighter.
    static func shade(app: String, index: Int) -> Color {
        let (h, s, b) = hsb(for: app)
        let steps = [0.0, -0.32, 0.12, -0.16]
        let nb = min(1.0, max(0.25, b + steps[index % steps.count]))
        return Color(hue: h, saturation: min(1.0, s + 0.05), brightness: nb)
    }
}
