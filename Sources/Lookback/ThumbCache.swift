import AppKit
import Foundation

/// Tiny thumbnail cache so the activity strip can show real previews.
enum ThumbCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumb(for shot: ShotStore.Shot, width: CGFloat = 64) -> NSImage? {
        if let hit = cache.object(forKey: shot.url as NSURL) { return hit }
        guard let img = NSImage(contentsOf: shot.url) else { return nil }
        let h = max(1, width * img.size.height / max(1, img.size.width))
        let t = NSImage(size: NSSize(width: width, height: h))
        t.lockFocus()
        img.draw(in: NSRect(x: 0, y: 0, width: width, height: h))
        t.unlockFocus()
        cache.setObject(t, forKey: shot.url as NSURL)
        return t
    }
}
