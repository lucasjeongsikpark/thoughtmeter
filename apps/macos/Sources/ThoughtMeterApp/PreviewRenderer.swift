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
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stats = sampleStats()
        render(
            DashboardSections(stats: stats, range: .today)
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-today.png", in: directory
        )
        render(
            DashboardSections(stats: stats, range: .week)
                .frame(width: 720)
                .padding(24)
                .background(Color(nsColor: .windowBackgroundColor)),
            name: "dashboard-week.png", in: directory
        )
        render(
            ShareCardView(stats: stats, includeSources: true),
            name: "proof-of-thought.png", in: directory
        )
        print("previews written to \(directory.path)")
        exit(0)
    }

    private static func render<Content: View>(_ view: Content, name: String, in directory: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("failed to render \(name)")
            return
        }
        try? png.write(to: directory.appendingPathComponent(name))
        print("rendered \(name)")
    }

    /// A realistic day: quiet morning, working-hours ramp, evening tail.
    private static func sampleStats() -> DashboardStats {
        var stats = DashboardStats()
        stats.hourly = [
            0, 0, 0, 0, 0, 0, 0, 120,
            980, 1740, 2210, 1830, 640, 1420, 2540, 2310,
            1680, 1150, 420, 260, 510, 180, 0, 0,
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
        stats.total = stats.hourly.reduce(0, +)
        stats.peakHour = stats.hourly.firstIndex(of: stats.hourly.max() ?? 0)
        stats.sevenDayAverage = 14_120
        stats.daily = [
            ("2026-07-29", 12_480), ("2026-07-30", 15_920), ("2026-07-31", 13_260),
            ("2026-08-01", 4_180), ("2026-08-02", 6_540), ("2026-08-03", 16_870),
            ("2026-08-04", stats.total),
        ]
        return stats
    }
}
