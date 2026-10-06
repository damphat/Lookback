import AppKit
import CoreGraphics
import Foundation

/// Sample producer (app-wide singleton: closing the window must NOT stop
/// capturing). Contract: while the user is present, every 60s tick emits one
/// timestamped sample — never a silent gap. Sleep is NOT recorded here; the
/// time-mapping side infers it from gaps.
/// - every 60s, on .utility queue
/// - skips only when paused, permission missing, or machine idle (no input
///   events for 10 min) to save CPU/battery
/// - downscales main display to max 1280px wide, JPEG ~0.45
final class CaptureService: ObservableObject {
    static let shared = CaptureService()

    @Published var paused = false
    @Published var permissionGranted = CGPreflightScreenCaptureAccess()
    /// Sticky Automation latch (mirrors `permissionGranted`): set the moment
    /// consent is proven missing — at launch or when Chrome is frontmost —
    /// cleared only when a check proves it granted. Never blinks.
    @Published var automationDenied = false
    /// Bumped on the main thread after every saved shot: open windows observe
    /// it and rescope, so new photos appear with no manual refresh.
    @Published private(set) var generation = 0

    private var timer: Timer?
    private let queue = DispatchQueue(label: "lookback.capture", qos: .utility)

    // Idle threshold: no key/mouse event for 10 min -> skip capture.
    private let idleThreshold: TimeInterval = 10 * 60

    private init() {}

    private var started = false
    func start() {
        guard !started else { return }
        started = true
        // Both gates are checked at launch (like Recording): a missing one
        // shows its banner the first time the window opens, no silent wait
        // until the background loop happens to touch it.
        refreshPermission()
        refreshAutomation()
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

    /// Check consent WITHOUT prompting. Safe to call anywhere, anytime.
    func refreshAutomation() {
        automationDenied = ActiveContext.chromeAutomationDenied()
    }

    /// THE one banner button: tries the real consent dialog first (works
    /// only before the first denial — afterwards macOS stays silent, which
    /// is why the old button looked "broken"). Still denied afterwards?
    /// Opens Settings directly, so the tap always visibly does something.
    func fixAutomation() {
        automationDenied = !ActiveContext.requestChromeAutomation()
        if automationDenied { Self.openAutomationSettings() }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
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

        let now = Date()
        // Best-effort context (frontmost app + Chrome domain / VSCode
        // folder). Nil parts are dropped, degrading to timestamp-only.
        // `current()` maintains the sticky denial latch as a side effect.
        let ctx = ActiveContext.current()
        let denied = ActiveContext.chromeDenied
        let url = ShotStore.dir.appendingPathComponent(
            ShotStore.filename(for: now, app: ctx.app, detail: ctx.detail))
        do {
            try jpg.write(to: url)
            DispatchQueue.main.async {
                // Sticky: only ever set here; cleared only by a granted
                // check (launch / banner tap), so the banner can't blink.
                if denied { self.automationDenied = true }
                self.generation += 1
            }
        } catch { return }
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
