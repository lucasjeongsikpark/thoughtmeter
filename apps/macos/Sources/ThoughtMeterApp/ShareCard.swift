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

    var body: some View {
        VStack(spacing: 14) {
            Text("Proof of Thought")
                .font(.headline)
            Text("Today’s trace, rendered locally as a 1200×630 image.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ShareCardView(stats: stats, includeSources: includeSources)
                .frame(width: 480, height: 252)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            Toggle("Include source breakdown", isOn: $includeSources)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save PNG…") { save() }
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
        try? png.write(to: url)
        dismiss()
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
                Text("Today’s Human Input")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(HumanInputFormatter.exact(stats.total))
                        .font(.system(size: 110, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("keystrokes")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                .padding(.top, 6)

                if includeSources {
                    HStack(spacing: 40) {
                        if let top = stats.bySource.first {
                            fact("Top tool", top.source.displayName)
                        }
                        if let peak = stats.peakHour {
                            fact("Peak hour", peakLabel(peak))
                        }
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
