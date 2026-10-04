import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// Battery-friendly capture loop:
/// - every 60s, on .utility queue
/// - skips capture when machine idle (no input events) to save CPU/battery
/// - skips saving when pixels identical to previous shot (static screen)
/// - downscales main display to max 1280px wide, JPEG ~0.45
final class CaptureService: ObservableObject {
    @Published var paused = false
    @Published var lastShotDate: Date?
    @Published var shotCount24h = 0

    private var timer: Timer?
    private var lastHash = ""
    private let queue = DispatchQueue(label: "lookback.capture", qos: .utility)

    // Idle threshold: no key/mouse event for 10 min -> skip capture.
    private let idleThreshold: TimeInterval = 10 * 60

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        stop()
        ShotStore.cleanup()
        capture() // capture once at launch
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.queue.async { self?.capture() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func idleSeconds() -> TimeInterval {
        // CGEventSource.secondsSinceLastEventType: .combinedSessionState
        let t = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0) ?? .null)
        return t.isFinite ? t : 0
    }

    private func capture() {
        if Thread.isMainThread { queue.async { self.capture() }; return }
        if paused { return }
        if idleSeconds() > idleThreshold { return } // user away -> save battery+disk

        guard CGPreflightScreenCaptureAccess() else { return }
        guard let img = CGDisplayCreateImage(CGMainDisplayID()) else { return }
        let small = downscale(img, maxWidth: 1280)
        guard let jpg = jpegData(of: small, quality: 0.45) else { return }

        // Skip duplicates: same pixels as last shot -> just touch nothing.
        let hash = String(Insecure.MD5.hash(data: jpg).prefix(8).map { String(format: "%02x", $0) }.joined())
        if hash == lastHash { return }
        lastHash = hash

        let url = ShotStore.dir.appendingPathComponent(
            ShotStore.fmt.string(from: Date()) + ".jpg")
        try? jpg.write(to: url)
        DispatchQueue.main.async {
            self.lastShotDate = Date()
            self.shotCount24h = ShotStore.list().filter {
                $0.date > Date().addingTimeInterval(-86400)
            }.count
        }
        // Opportunistic cleanup once per capture.
        ShotStore.cleanup()
    }

    private func downscale(_ img: CGImage, maxWidth: Int) -> CGImage {
        let w = img.width
        guard w > maxWidth else { return img }
        let scale = CGFloat(maxWidth) / CGFloat(w)
        let h = Int(CGFloat(img.height) * scale)
        let ctx = CGContext(data: nil, width: maxWidth, height: h,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ctx?.interpolationQuality = .low
        ctx?.draw(img, in: CGRect(x: 0, y: 0, width: maxWidth, height: h))
        return ctx?.makeImage() ?? img
    }

    private func jpegData(of img: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
