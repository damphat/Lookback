import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// Battery-friendly capture loop (app-wide singleton: closing the window
/// must NOT stop capturing).
/// - every 60s, on .utility queue
/// - skips capture when machine idle (no input events) to save CPU/battery
/// - skips saving when pixels identical to previous shot (static screen)
/// - downscales main display to max 1280px wide, JPEG ~0.45
final class CaptureService: ObservableObject {
    static let shared = CaptureService()

    @Published var paused = false
    @Published var permissionGranted = CGPreflightScreenCaptureAccess()
    /// True when Chrome was frontmost but Automation consent is missing
    /// (domain capture silently degraded). Mirrors `permissionGranted`.
    @Published var automationDenied = false

    private var timer: Timer?
    private var lastHash = ""
    private let queue = DispatchQueue(label: "lookback.capture", qos: .utility)

    // Idle threshold: no key/mouse event for 10 min -> skip capture.
    private let idleThreshold: TimeInterval = 10 * 60

    private init() {}

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        permissionGranted = CGPreflightScreenCaptureAccess()
        ShotStore.cleanup()
        queue.async { self.capture() } // capture once at launch
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.capture() }
        }
    }

    /// Ask the OS for Screen Recording permission. Call ONLY from an explicit
    /// user tap — never automatically — or macOS nags on every launch.
    func requestPermission() {
        CGRequestScreenCaptureAccess()
        // Re-check shortly after (user may grant in Settings).
        queue.asyncAfter(deadline: .now() + 2) {
            let ok = CGPreflightScreenCaptureAccess()
            DispatchQueue.main.async { self.permissionGranted = ok }
        }
    }

    func refreshPermission() {
        permissionGranted = CGPreflightScreenCaptureAccess()
    }

    /// User-tapped consent request: pops the real system dialog and creates
    /// the Automation entry for THIS binary. Call only from explicit UI.
    func requestAutomation() {
        automationDenied = !ActiveContext.requestChromeAutomation()
    }

    private func idleSeconds() -> TimeInterval {
        // hidSystemState + kCGAnyInputEventType (0xFFFFFFFF) = standard idle time.
        let t = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: 0xFFFFFFFF) ?? .null)
        return t.isFinite && t >= 0 ? t : 0
    }

    private func capture() {
        if paused { return }

        let granted = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async { self.permissionGranted = granted }
        guard granted else { return }
        guard idleSeconds() <= idleThreshold else { return } // user away

        guard let img = CGDisplayCreateImage(CGMainDisplayID()) else { return }
        let small = downscale(img, maxWidth: 1280)
        guard let jpg = jpegData(of: small, quality: 0.45) else { return }

        // Skip duplicates: same pixels as last shot -> save disk + battery.
        let digest = Insecure.MD5.hash(data: jpg)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        if hash == lastHash { return }
        lastHash = hash

        let now = Date()
        // Best-effort context (frontmost app + Chrome domain / VSCode
        // folder). Nil parts are dropped, degrading to timestamp-only.
        let ctx = ActiveContext.current()
        let denied = ActiveContext.chromeDenied
        DispatchQueue.main.async { self.automationDenied = denied }
        let url = ShotStore.dir.appendingPathComponent(
            ShotStore.filename(for: now, app: ctx.app, detail: ctx.detail))
        try? jpg.write(to: url)
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
