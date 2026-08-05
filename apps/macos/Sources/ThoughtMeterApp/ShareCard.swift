import AppKit
import SwiftUI
import ThoughtMeterKit

/// "Proof of Thought" — user-initiated card export: renders a 1200×630 PNG
/// locally and saves it through a standard Save dialog. Nothing is uploaded
/// anywhere.
struct ShareCardSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    let stats: DashboardStats
    @State private var includeSources = true

    private let previewScale: CGFloat = 0.4

    var body: some View {
        VStack(spacing: 14) {
            Text("Share your Proof of Thought")
                .font(.headline)
            Text("Today’s trace, rendered locally as a 1200×630 image. Nothing is uploaded — you choose where it goes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Preview at 40%: the card lays out at its full fixed size, the
            // scale effect shrinks the rendering, and the outer frame crops
            // the (now matching) visual bounds — without this, SwiftUI clips
            // a zoomed-in center region instead of showing the whole card.
            ShareCardView(stats: stats, includeSources: includeSources)
                .scaleEffect(previewScale)
                .frame(width: 1200 * previewScale, height: 630 * previewScale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            Toggle("Include source breakdown", isOn: $includeSources)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Image…") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func save() {
        let renderer = ImageRenderer(content: ShareCardView(stats: stats, includeSources: includeSources)
            .frame(width: 1200, height: 630))
        renderer.scale = 1.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "proof-of-thought.png"
        panel.title = "Save Proof of Thought"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            dismiss()
        } catch {
            // Keep the sheet open so the user can pick another destination.
            let alert = NSAlert()
            alert.messageText = "ThoughtMeter"
            alert.informativeText = "Could not save the image: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

/// The card itself. Fixed light design so the exported PNG is predictable.
struct ShareCardView: View {
    let stats: DashboardStats
    let includeSources: Bool

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.955)

            VStack(alignment: .leading, spacing: 0) {
                Text("Today’s Thought Input")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(CountFormatter.exact(stats.total))
                        .font(.system(size: 110, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("keystrokes")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                .padding(.top, 6)

                if includeSources {
                    VStack(alignment: .leading, spacing: 22) {
                        // No "Top tool" fact: the breakdown's first row is the
                        // top tool, and printing it twice reads as a mistake.
                        if let peak = stats.peakHour {
                            fact("Peak hour", peakLabel(peak))
                        }
                        breakdown
                    }
                    .padding(.top, 26)
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not every keystroke is a thought.")
                        Text("But thinking leaves traces.")
                    }
                    .font(.system(size: 25, weight: .medium, design: .serif).italic())
                    .foregroundStyle(Color.black.opacity(0.65))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("ThoughtMeter")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.75))
                        Text(ReleaseConfig.repositoryURLString)
                            .font(.system(size: 17, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                }
            }
            .padding(56)
        }
        .frame(width: 1200, height: 630)
    }

    /// Top sources as name + proportional bar + exact count. Text-only (no
    /// app icons): ImageRenderer runs outside a window, so keeping the card to
    /// vector text and shapes makes the export deterministic.
    @ViewBuilder
    private var breakdown: some View {
        let rows = Array(stats.bySource.prefix(3))
        let maximum = rows.first?.keystrokes ?? 0
        if maximum > 0 {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 18) {
                        Text(row.source.displayName)
                            .font(.system(size: 25))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .lineLimit(1)
                            .frame(width: 300, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 420, height: 12)
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: max(12, 420 * barRatio(row.keystrokes, of: maximum)),
                                       height: 12)
                        }

                        Text(CountFormatter.exact(row.keystrokes))
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
            }
        }
    }

    private func barRatio(_ value: Int, of maximum: Int) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(value) / CGFloat(maximum)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20))
                .foregroundStyle(Color.black.opacity(0.4))
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
        }
    }

    private func peakLabel(_ hour: Int) -> String {
        func label(_ h: Int) -> String {
            switch h {
            case 0: return "12 AM"
            case 1..<12: return "\(h) AM"
            case 12: return "12 PM"
            default: return "\(h - 12) PM"
            }
        }
        return "\(label(hour))–\(label((hour + 1) % 24))"
    }
}
