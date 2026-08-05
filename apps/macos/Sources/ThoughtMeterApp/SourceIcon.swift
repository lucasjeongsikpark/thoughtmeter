import AppKit
import SwiftUI
import ThoughtMeterKit

/// Cached source icons. App icons come from the installed bundle via
/// NSWorkspace (looked up once per bundle ID, then cached — icon lookups
/// hit the disk, so they must never run repeatedly in list renders).
@MainActor
enum IconCache {
    private static var appIcons: [String: NSImage?] = [:]

    static func appIcon(forBundleID bundleID: String) -> NSImage? {
        if let cached = appIcons[bundleID] { return cached }
        var icon: NSImage? = nil
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 32, height: 32)
            icon = image
        }
        appIcons[bundleID] = icon
        return icon
    }
}

/// A small leading mark identifying a source.
/// - Apps: the real app icon (dashed placeholder if no longer installed).
/// - Domains: the companion desktop app's icon when installed (accurate
///   brand mark read from the user's own machine), otherwise a colored
///   monogram tile — the same idea as a browser's favicon fallback.
///   Favicons are never fetched: ThoughtMeter makes no network requests.
struct SourceIcon: View {
    let source: SourceRecord
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch source.kind {
            case .app:
                if let icon = IconCache.appIcon(forBundleID: source.identifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .fontWeight(.light)
                        .foregroundStyle(.secondary)
                        .padding(1)
                }
            case .domain:
                if let companionID = RecognizedCatalog.domainCompanionApps[source.identifier],
                   let icon = IconCache.appIcon(forBundleID: companionID) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    MonogramIcon(source: source, size: size)
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }
}

/// Favicon-style fallback: rounded tile in a stable per-domain color with
/// the first letter of the display name.
private struct MonogramIcon: View {
    let source: SourceRecord
    let size: CGFloat

    /// Fixed muted palette; hues are assigned deterministically per domain,
    /// never generated (a re-launch or list change must not repaint icons).
    private static let palette: [Color] = [
        Color(red: 0.35, green: 0.48, blue: 0.79), // slate blue
        Color(red: 0.72, green: 0.42, blue: 0.28), // clay
        Color(red: 0.33, green: 0.60, blue: 0.52), // sea green
        Color(red: 0.58, green: 0.42, blue: 0.68), // plum
        Color(red: 0.76, green: 0.55, blue: 0.22), // ochre
        Color(red: 0.42, green: 0.56, blue: 0.66), // steel
        Color(red: 0.69, green: 0.38, blue: 0.48), // rose
        Color(red: 0.45, green: 0.55, blue: 0.35), // moss
    ]

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(Self.palette[paletteIndex])
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }

    private var letter: String {
        String(source.displayName.first ?? source.identifier.first ?? "•").uppercased()
    }

    /// djb2 over the identifier — stable across launches (Swift's Hashable
    /// is seeded per process and must not be used here).
    private var paletteIndex: Int {
        var hash: UInt64 = 5381
        for scalar in source.identifier.unicodeScalars {
            hash = (hash << 5) &+ hash &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(Self.palette.count))
    }
}
