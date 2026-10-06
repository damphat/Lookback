import Foundation

/// Single source of truth for the activity bar.
///
/// Mental model: the state owns timestamped samples (one per screenshot)
/// plus the visible window (default: -24h … now). Everything the bar needs —
/// two-level render regions and rich hover info — is derived from it, so the
/// SwiftUI view stays dumb and every rule is unit-testable.
///
/// - Every sample owns one time cell (midpoint split with neighbours,
///   capped at ±sleepGap/2). Regions are unions of cells, so photo counts
///   and time spans agree by construction — no padding, no clamp passes.
/// - Level 1: app run (contiguous same-app cells) or sleep (the complement).
/// - Level 2: contiguous same-detail cells inside a run.
/// - `view(at:in:)` is the only lookup the UI may display.
struct ActivityState {
    struct Sample: Hashable {
        let date: Date
        let app: String?
        let detail: String?
        var resolvedApp: String { app ?? ActivityState.unknownApp }
    }

    enum Kind: Equatable {
        case sleep
        case app(String)
        var appName: String? {
            if case .app(let a) = self { return a }
            return nil
        }
    }

    struct ChildRegion: Equatable {
        let detail: String
        let start: Date
        let end: Date
        let count: Int
        var minutes: Int { Int(round(end.timeIntervalSince(start) / 60)) }
    }

    struct Region: Equatable, Identifiable {
        var id: String { "\(kind)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
        let kind: Kind
        let start: Date
        let end: Date
        let count: Int
        /// All child detail runs (already ordered by start). Render callers
        /// draw all (they are disjoint); hover callers use `topDetails()`,
        /// never a raw `prefix(5)` over runs.
        let children: [ChildRegion]
        var isSleep: Bool { kind == .sleep }
        var minutes: Int { Int(round(end.timeIntervalSince(start) / 60)) }

        /// Top details by total time in this region, most-used first.
        ///
        /// Children are contiguous same-detail runs, so one detail (a
        /// website, file, doc…) can appear in several non-adjacent runs.
        /// This groups those runs by detail string, sums exact durations,
        /// sorts desc, and caps at `limit`. Tie-break is by detail name so
        /// the order is deterministic. Detail is opaque — no per-app
        /// branching — so this holds for every tiered app, not just Chrome.
        func topDetails(limit: Int = 5) -> [(detail: String, minutes: Int)] {
            var acc: [String: TimeInterval] = [:]
            for c in children {
                acc[c.detail, default: 0] += c.end.timeIntervalSince(c.start)
            }
            return acc.map { (detail: $0.key, minutes: Int(round($0.value / 60))) }
                .sorted {
                    if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
                    return $0.detail < $1.detail
                }
                .prefix(limit)
                .map { $0 }
        }
    }

    static let unknownApp = "Unknown"
    /// The single threshold: neighbours more than this apart leave sleep
    /// between them; closer ones share an exact cell edge. Cells extend at
    /// most sleepGap/2 from their sample.
    static let sleepGap: TimeInterval = 5 * 60


    private(set) var samples: [Sample] = []
    private(set) var from: Date
    private(set) var to: Date

    init(from: Date = Date().addingTimeInterval(-24 * 3600), to: Date = Date()) {
        self.from = from
        self.to = to
    }

    /// Bulk init from already-sorted shots. The view builds this ONCE per
    /// (shots, window) and passes it down — never rebuild per hover/drag.
    init(samples shots: [ShotStore.Shot], from: Date, to: Date) {
        self.from = from
        self.to = to
        self.samples = shots.map { Sample(date: $0.date, app: $0.app, detail: $0.detail) }
            .sorted { $0.date < $1.date }
    }

    mutating func addSample(date: Date, app: String?, detail: String?) {
        let s = Sample(date: date, app: app?.isEmpty == true ? nil : app, detail: detail?.isEmpty == true ? nil : detail)
        let i = samples.firstIndex(where: { $0.date > date }) ?? samples.endIndex
        samples.insert(s, at: i)
    }

    mutating func setView(from: Date, to: Date) {
        precondition(from < to, "view window must be non-empty")
        self.from = from
        self.to = to
    }

    // MARK: - Regions (two levels)

    /// One mapping only: every sample owns a time cell, and regions are
    /// unions of cells — so counts and durations agree by construction.
    ///
    /// - Cell i spans to the midpoints with its neighbours (Voronoi split),
    ///   capped at ±sleepGap/2. Neighbours closer than sleepGap share an
    ///   exact edge (no gap, no overlap); farther apart leaves sleep between.
    /// - A run = contiguous same-app cells with no sleep between. Children =
    ///   contiguous same-detail cells inside a run (nil detail = base colour).
    /// - Sleep = the complement of all cells in [from, to].
    func regions() -> [Region] {
        let inView = samples.filter { $0.date >= from && $0.date <= to }
        guard !inView.isEmpty else {
            return [Region(kind: .sleep, start: from, end: to, count: 0, children: [])]
        }
        let cap = Self.sleepGap / 2
        var lo = [Date](repeating: from, count: inView.count)
        var hi = [Date](repeating: to, count: inView.count)
        for i in inView.indices {
            if i > 0 {
                let gap = inView[i].date.timeIntervalSince(inView[i - 1].date)
                lo[i] = gap > Self.sleepGap
                    ? inView[i].date.addingTimeInterval(-cap)
                    : inView[i - 1].date.addingTimeInterval(gap / 2)
            } else if inView[i].date.timeIntervalSince(from) > Self.sleepGap {
                lo[i] = inView[i].date.addingTimeInterval(-cap)
            }
            if i + 1 < inView.count {
                let gap = inView[i + 1].date.timeIntervalSince(inView[i].date)
                hi[i] = gap > Self.sleepGap
                    ? inView[i].date.addingTimeInterval(cap)
                    : inView[i].date.addingTimeInterval(gap / 2)
            } else if to.timeIntervalSince(inView[i].date) > Self.sleepGap {
                hi[i] = inView[i].date.addingTimeInterval(cap)
            }
            lo[i] = max(lo[i], from)
            hi[i] = min(hi[i], to)
        }
        // Run boundaries: app change, or a sleep-sized gap (cells don't touch).
        var starts = [0]
        for i in 1..<inView.count where inView[i].resolvedApp != inView[i - 1].resolvedApp
            || lo[i] > hi[i - 1] {
            starts.append(i)
        }
        var out: [Region] = []
        var cursor = from
        func children(of s: Int, through e: Int) -> [ChildRegion] {
            var kids: [ChildRegion] = []
            var k = s
            while k <= e {
                guard let d = inView[k].detail else { k += 1; continue }
                var j = k
                while j + 1 <= e && inView[j + 1].detail == d { j += 1 }
                kids.append(ChildRegion(detail: d, start: lo[k], end: hi[j], count: j - k + 1))
                k = j + 1
            }
            return kids
        }
        for b in starts.indices {
            let s = starts[b]
            let e = (b + 1 < starts.count) ? starts[b + 1] - 1 : inView.count - 1
            if lo[s] > cursor {
                out.append(Region(kind: .sleep, start: cursor, end: lo[s], count: 0, children: []))
            }
            out.append(Region(kind: .app(inView[s].resolvedApp), start: lo[s], end: hi[e],
                              count: e - s + 1, children: children(of: s, through: e)))
            cursor = hi[e]
        }
        if cursor < to {
            out.append(Region(kind: .sleep, start: cursor, end: to, count: 0, children: []))
        }
        return out
    }

    // MARK: - Lookup

    /// THE single answer to "what is at time t". Both the bar (hover card,
    /// rendered highlight) and the viewer (image, status line) must use this
    /// and nothing else — region membership decides sleep vs app, and the
    /// shot is the nearest sample inside that region (no separate tolerance
    /// per caller, which was the source of hover/viewer disagreement).
    enum ViewAt {
        case app(sample: Sample, region: Region)
        case sleep(region: Region?)
        case empty
    }

    func view(at t: Date, in regs: [Region]) -> ViewAt {
        guard let r = regs.first(where: { $0.start <= t && t <= $0.end }) else { return .empty }
        switch r.kind {
        case .sleep:
            return .sleep(region: r)
        case .app:
            guard let s = nearestSample(to: t, from: r.start, through: r.end) else {
                return .sleep(region: r)
            }
            return .app(sample: s, region: r)
        }
    }

    /// Nearest sample to `t` among those in [lo, hi] (binary-search bounds,
    /// linear only inside the run). Nil when the range holds no samples.
    func nearestSample(to t: Date, from lo: Date, through hi: Date) -> Sample? {
        var a = 0, b = samples.count
        while a < b {
            let m = (a + b) / 2
            if samples[m].date < lo { a = m + 1 } else { b = m }
        }
        var best: Sample?
        var bestDelta = TimeInterval.infinity
        var i = a
        while i < samples.count && samples[i].date <= hi {
            let d = abs(samples[i].date.timeIntervalSince(t))
            if d < bestDelta { bestDelta = d; best = samples[i] }
            i += 1
        }
        return best
    }

    // MARK: - Summary (time-domain stats; the view never counts photos)

    struct SummaryRow {
        let app: String
        let minutes: Int
        /// (detail, minutes) sorted desc.
        let details: [(String, Int)]
    }

    /// Active minutes per app (+ per detail) in this window, sorted desc.
    /// Durations come from regions, so stats always agree with the bar.
    func summary() -> [SummaryRow] {
        var acc: [String: (Int, [String: Int])] = [:]
        for r in regions() {
            guard let app = r.kind.appName else { continue }
            var (m, d) = acc[app] ?? (0, [:])
            m += r.minutes
            for c in r.children { d[c.detail, default: 0] += c.minutes }
            acc[app] = (m, d)
        }
        return acc.map { app, v in
            SummaryRow(app: app, minutes: v.0,
                       details: v.1.sorted { $0.value > $1.value })
        }.sorted { $0.minutes > $1.minutes }
    }

    // MARK: - Benchmark helper

    /// Synthetic state: `count` one-minute samples cycling `apps`, with
    /// `detailEvery`-th sample carrying a detail. For perf/stress tests.
    static func synthetic(count: Int, apps: [String] = ["Chrome", "Xcode", "Slack"], detailEvery: Int = 3, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ActivityState {
        var st = ActivityState(from: base, to: base.addingTimeInterval(Double(count * 60)))
        for i in 0..<count {
            st.addSample(date: base.addingTimeInterval(Double(i * 60)),
                         app: apps[i % apps.count],
                         detail: i % detailEvery == 0 ? "detail-\(i % 5)" : nil)
        }
        return st
    }
}
