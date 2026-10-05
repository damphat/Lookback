import CoreGraphics

/// Single source of truth for timeline strip geometry + cell/fraction mapping.
///
/// Tap position and displayed moment must agree: tapping cell `i` selects the
/// cell centre `(i + 0.5) / cells`, which is also the moment `repShot` uses.
/// The old code tapped `i / (cells - 1)` (cell leading edge on a slider
/// scale) while the thumbnail represented the bucket centre, so the shown
/// image could belong to a neighbouring cell.
enum TimelineLayout {
    static let cellHeight: CGFloat = 28
    static let cellSpacing: CGFloat = 2
    static let cellCornerRadius: CGFloat = 3

    /// Fraction (slider scale 0...1) for the centre of cell `i`.
    static func fraction(forCell i: Int, cells: Int) -> Double {
        let clamped = min(max(i, 0), cells - 1)
        return (Double(clamped) + 0.5) / Double(cells)
    }

    /// Cell index containing a fraction.
    static func cellIndex(forFraction fraction: Double, cells: Int) -> Int {
        min(cells - 1, max(0, Int(floor(fraction * Double(cells)))))
    }
}
