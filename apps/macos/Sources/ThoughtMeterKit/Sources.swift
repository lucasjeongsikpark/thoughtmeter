import Foundation

/// What kind of thing a tracked source is.
public enum SourceKind: String, Codable, CaseIterable {
    /// A macOS application, identified by bundle identifier.
    case app
    /// A website, identified by normalized domain (Chrome only in v0.1).
    case domain
}

/// A source as configured by the user (input to persistence).
public struct SourceDescriptor: Equatable {
    public var kind: SourceKind
    /// Bundle identifier (`com.apple.Terminal`) or normalized domain (`claude.ai`).
    public var identifier: String
    public var displayName: String
    public var isBuiltin: Bool

    public init(kind: SourceKind, identifier: String, displayName: String, isBuiltin: Bool) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.isBuiltin = isBuiltin
    }
}

/// A source as stored in SQLite.
public struct SourceRecord: Equatable, Identifiable {
    public let id: Int64
    public var kind: SourceKind
    public var identifier: String
    public var displayName: String
    public var isBuiltin: Bool
    public var isEnabled: Bool
    public var createdAt: Int64

    public init(id: Int64, kind: SourceKind, identifier: String, displayName: String,
                isBuiltin: Bool, isEnabled: Bool, createdAt: Int64) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.isBuiltin = isBuiltin
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

/// The applications and domains ThoughtMeter recognizes out of the box.
/// This list ships with the app and changes only with a new release —
/// there is no remote configuration.
public enum RecognizedCatalog {
    public struct App: Equatable {
        public let displayName: String
        public let bundleID: String
    }

    /// Candidate AI tools / workspaces. At runtime the app verifies each
    /// bundle ID against actually installed applications before offering or
    /// (in "All recognized" mode) enabling it.
    public static let apps: [App] = [
        App(displayName: "ChatGPT", bundleID: "com.openai.chat"),
        App(displayName: "Claude", bundleID: "com.anthropic.claudefordesktop"),
        App(displayName: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        App(displayName: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        App(displayName: "Terminal", bundleID: "com.apple.Terminal"),
        App(displayName: "iTerm2", bundleID: "com.googlecode.iterm2"),
        App(displayName: "Warp", bundleID: "dev.warp.Warp-Stable"),
        App(displayName: "Zed", bundleID: "dev.zed.Zed"),
        App(displayName: "Windsurf", bundleID: "com.exafunction.windsurf"),
    ]

    /// Recognized AI domains for Chrome tracking.
    public static let domains: [(displayName: String, domain: String)] = [
        ("ChatGPT (web)", "chatgpt.com"),
        ("Claude (web)", "claude.ai"),
    ]

    /// Chrome variants. These are handled exclusively through domain tracking;
    /// they must never be added as generic app sources (that would count
    /// typing on every website).
    public static let chromeBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
    ]

    public static func isChrome(bundleID: String) -> Bool {
        chromeBundleIDs.contains(bundleID)
    }
}
