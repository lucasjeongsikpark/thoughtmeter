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

/// A small leading mark identifying a source: the real app icon for apps,
/// a globe for domains, and a dashed placeholder for apps that are no
/// longer installed.
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
                Image(systemName: "globe")
                    .resizable()
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .padding(1)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    }
}
