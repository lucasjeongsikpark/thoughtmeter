import AppKit
import SwiftUI
import ThoughtMeterKit

/// Developer utility: `ThoughtMeter --render-previews <dir>` renders the
/// dashboard sections and the Proof of Thought card to PNGs offscreen and
/// exits. Used to visually verify chart rendering without a GUI session,
/// and to produce README/store screenshots deterministically.
@MainActor
enum PreviewRenderer {
    static func runIfRequested() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--render-previews"),
              CommandLine.arguments.count > flagIndex + 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("failed to create \(directory.path): \(error)")
            exit(1)
        }

        let stats = sampleStats()
        // A failed render/write must fail the run — printing success and
        // exiting 0 would let a visual check "pass" against stale or
        // missing images.
        let renderedToday = render(
            DashboardSections(stats: stats, range: .today)
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-today.png", in: directory
        )
        let renderedWeek = render(
            DashboardSections(stats: sampleWeekStats(), range: .week)
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-week.png", in: directory
        )
        // The hover readouts, pinned open. Hour 9 sits mid-chart; the last
        // day exercises the annotation's fit-to-chart clamping at the right
        // edge, where an unclamped tooltip would spill out of the card.
        let renderedHover = render(
            DashboardSections(stats: sampleWeekStats(), range: .week,
                              // A non-nil handler is what adds the click
                              // hint, so the render must supply one.
                              onSelectDay: { _ in },
                              previewHoveredDate: "2026-08-04")
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-hover-day.png", in: directory
        )
        let renderedHourHover = render(
            DashboardSections(stats: stats, range: .today, previewHoveredHour: 9)
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-hover-hour.png", in: directory
        )
        // The day view a by-day bar click opens: same sections as Today,
        // minus the range-only comparison card and the 7-day trend.
        let renderedDay = render(
            DashboardSections(stats: sampleDayStats(), range: .week, dayDate: "2026-08-03")
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-day.png", in: directory
        )
        let renderedCard = render(
            ShareCardView(stats: stats, range: .today, includeSources: true),
            name: "proof-of-thought.png", in: directory
        )
        guard renderedToday && renderedWeek && renderedDay
                && renderedHover && renderedHourHover && renderedCard else { exit(1) }
        print("previews written to \(directory.path)")
        exit(0)
    }

    private static func render<Content: View>(_ view: Content, name: String, in directory: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("failed to render \(name)")
            return false
        }
        do {
            try png.write(to: directory.appendingPathComponent(name))
        } catch {
            print("failed to write \(name): \(error)")
            return false
        }
        print("rendered \(name)")
        return true
    }

    /// A realistic day: quiet morning, working-hours ramp, evening tail.
    private static func sampleStats() -> DashboardStats {
        var stats = DashboardStats()
        // Must sum to the same total as the sources below — the real app
        // derives total from the source sum, so a preview where the two
        // disagree depicts an impossible state.
        stats.hourly = [
            0, 0, 0, 0, 0, 0, 0, 120,
            980, 1740, 2210, 1830, 640, 1420, 2140, 2010,
            1530, 1150, 420, 260, 510, 180, 0, 0,
        ]
        let sources: [(SourceRecord, Int)] = [
            (SourceRecord(id: 1, kind: .app, identifier: "com.microsoft.VSCode",
                          displayName: "Visual Studio Code", isBuiltin: true, isEnabled: true, createdAt: 0), 6840),
            (SourceRecord(id: 2, kind: .app, identifier: "com.anthropic.claudefordesktop",
                          displayName: "Claude", isBuiltin: true, isEnabled: true, createdAt: 0), 4210),
            (SourceRecord(id: 3, kind: .domain, identifier: "chatgpt.com",
                          displayName: "ChatGPT (web)", isBuiltin: true, isEnabled: true, createdAt: 0), 2705),
            (SourceRecord(id: 4, kind: .app, identifier: "com.apple.Terminal",
                          displayName: "Terminal", isBuiltin: true, isEnabled: true, createdAt: 0), 1930),
            (SourceRecord(id: 5, kind: .domain, identifier: "gemini.google.com",
                          displayName: "Gemini", isBuiltin: true, isEnabled: true, createdAt: 0), 1105),
            (SourceRecord(id: 6, kind: .domain, identifier: "internal.mycompany.dev",
                          displayName: "internal.mycompany.dev", isBuiltin: false, isEnabled: true, createdAt: 0), 350),
        ]
        stats.bySource = sources
        stats.total = sources.reduce(0) { $0 + $1.1 }
        assert(stats.total == stats.hourly.reduce(0, +), "sample hourly and source sums must agree")
        stats.peakHour = stats.hourly.firstIndex(of: stats.hourly.max() ?? 0)
        stats.sevenDayAverage = 14_120
        stats.daily = [
            ("2026-07-29", 12_480), ("2026-07-30", 15_920), ("2026-07-31", 13_260),
            ("2026-08-01", 4_180), ("2026-08-02", 6_540), ("2026-08-03", 16_870),
            ("2026-08-04", stats.total),
        ]
        return stats
    }

    /// One inspected past day. It carries no `daily` series and no 7-day
    /// average on purpose: the day view must not render either, so a preview
    /// that supplied them could hide a regression that does.
    private static func sampleDayStats() -> DashboardStats {
        var stats = sampleStats()
        stats.daily = []
        stats.sevenDayAverage = nil
        return stats
    }

    /// The week render shows "Total (7 Days)", the daily average, and the
    /// by-day chart from one stats object — so its total must equal the sum
    /// of the daily bars (and the source split must sum to that same total),
    /// or the preview depicts an impossible state.
    private static func sampleWeekStats() -> DashboardStats {
        var stats = sampleStats()
        let weekTotal = stats.daily.reduce(0) { $0 + $1.keystrokes }
        var scaled = stats.bySource.map {
            (source: $0.source, keystrokes: $0.keystrokes * weekTotal / stats.total)
        }
        // Integer scaling loses a remainder; pin it on the top source so the
        // breakdown still sums exactly to the total.
        if let first = scaled.first {
            let shortfall = weekTotal - scaled.reduce(0) { $0 + $1.keystrokes }
            scaled[0] = (first.source, first.keystrokes + shortfall)
        }
        stats.bySource = scaled
        stats.total = weekTotal
        assert(stats.total == stats.daily.reduce(0) { $0 + $1.keystrokes },
               "sample week total and daily sums must agree")
        assert(stats.total == stats.bySource.reduce(0) { $0 + $1.keystrokes },
               "sample week total and source sums must agree")
        return stats
    }
}
