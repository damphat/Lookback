import CoreGraphics
import Foundation

/// Pure window-frame memory: which frame to use when (re)opening the main
/// window. The remembered SIZE always wins; the origin is kept only when it
/// still lands on-screen, otherwise the window is re-centered (covers
/// unplugged monitors / changed resolutions).
enum WindowFrame {
    static func restored(
        saved: CGRect?,
        minSize: CGSize,
        defaultSize: CGSize,
        visible: CGRect
    ) -> CGRect {
        var size = defaultSize
        var savedOrigin: CGPoint?
        if let s = saved, s.width >= minSize.width, s.height >= minSize.height {
            size = s.size
            savedOrigin = s.origin
        }
        if let o = savedOrigin, visible.intersects(CGRect(origin: o, size: size)) {
            return CGRect(origin: o, size: size)
        }
        return CGRect(
            origin: CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2),
            size: size)
    }
}
