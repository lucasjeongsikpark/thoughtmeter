import Foundation

/// Chrome extension IDs are exactly 32 characters from the letters a–p
/// (a SHA-256 prefix re-encoded into that alphabet).
///
/// Validation matters beyond cosmetics: Chrome treats a native messaging
/// host manifest's `allowed_origins` as all-or-nothing — one malformed
/// origin pattern invalidates the whole manifest, severing the connection
/// for every listed extension. A typo saved as the development ID would
/// otherwise silently break the Web Store extension's connection too.
public enum ChromeExtensionID {
    private static let alphabet = Set("abcdefghijklmnop")

    public static func isPlausible(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { alphabet.contains($0) }
    }
}
