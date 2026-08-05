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
    /// (in "All recognized" mode) enabling it — an entry whose ID does not
    /// match a real installed bundle is simply never shown, so this list can
    /// be generous without risk.
    public static let apps: [App] = [
        // AI chat / assistant apps
        App(displayName: "ChatGPT", bundleID: "com.openai.chat"),
        App(displayName: "Claude", bundleID: "com.anthropic.claudefordesktop"),
        App(displayName: "Perplexity", bundleID: "ai.perplexity.mac"),
        App(displayName: "Microsoft Copilot", bundleID: "com.microsoft.Copilot"),
        App(displayName: "Grok", bundleID: "ai.x.grok"),
        App(displayName: "Raycast", bundleID: "com.raycast.macos"),
        // Local model runners
        App(displayName: "LM Studio", bundleID: "ai.elementlabs.lmstudio"),
        App(displayName: "Ollama", bundleID: "com.electron.ollama"),
        App(displayName: "Jan", bundleID: "jan.ai.app"),
        // AI-assisted editors / IDEs
        App(displayName: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        App(displayName: "VS Code Insiders", bundleID: "com.microsoft.VSCodeInsiders"),
        App(displayName: "VSCodium", bundleID: "com.vscodium"),
        App(displayName: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        App(displayName: "Windsurf", bundleID: "com.exafunction.windsurf"),
        App(displayName: "Zed", bundleID: "dev.zed.Zed"),
        App(displayName: "Zed Preview", bundleID: "dev.zed.Zed-Preview"),
        App(displayName: "Trae", bundleID: "com.trae.app"),
        App(displayName: "Xcode", bundleID: "com.apple.dt.Xcode"),
        App(displayName: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij"),
        App(displayName: "IntelliJ IDEA CE", bundleID: "com.jetbrains.intellij.ce"),
        App(displayName: "PyCharm", bundleID: "com.jetbrains.pycharm"),
        App(displayName: "PyCharm CE", bundleID: "com.jetbrains.pycharm.ce"),
        App(displayName: "WebStorm", bundleID: "com.jetbrains.WebStorm"),
        // Terminals (Claude Code, Codex CLI, and other terminal AI workflows)
        App(displayName: "Terminal", bundleID: "com.apple.Terminal"),
        App(displayName: "iTerm2", bundleID: "com.googlecode.iterm2"),
        App(displayName: "Warp", bundleID: "dev.warp.Warp-Stable"),
        App(displayName: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        App(displayName: "Alacritty", bundleID: "org.alacritty"),
        App(displayName: "kitty", bundleID: "net.kovidgoyal.kitty"),
        App(displayName: "WezTerm", bundleID: "com.github.wez.wezterm"),
    ]

    /// Recognized AI domains for Chrome tracking. All entries must pass
    /// DomainNormalizer.normalize unchanged (enforced by a catalog test).
    public static let domains: [(displayName: String, domain: String)] = [
        ("ChatGPT (web)", "chatgpt.com"),
        ("Claude (web)", "claude.ai"),
        ("Gemini", "gemini.google.com"),
        ("Google AI Studio", "aistudio.google.com"),
        ("NotebookLM", "notebooklm.google.com"),
        ("Perplexity (web)", "perplexity.ai"),
        ("Microsoft Copilot (web)", "copilot.microsoft.com"),
        ("Grok", "grok.com"),
        ("DeepSeek", "chat.deepseek.com"),
        ("Le Chat (Mistral)", "chat.mistral.ai"),
        ("Poe", "poe.com"),
        ("Character.AI", "character.ai"),
        ("Meta AI", "meta.ai"),
        ("Qwen Chat", "chat.qwen.ai"),
        ("Kimi", "kimi.com"),
        ("Wrtn", "wrtn.ai"),
        ("CLOVA X", "clova-x.naver.com"),
        ("v0", "v0.dev"),
        ("Lovable", "lovable.dev"),
        ("Bolt", "bolt.new"),
        ("Replit", "replit.com"),
        ("Midjourney", "midjourney.com"),
    ]

    /// Domain → desktop-app sibling. Used only for UI, as the middle step of
    /// the domain icon chain (bundled favicon → companion app icon →
    /// monogram): when a domain has no bundled favicon but its desktop app
    /// is installed, that app's icon — read from the user's own machine —
    /// identifies the domain. Favicons are bundled at development time,
    /// never fetched at runtime: the app makes no network requests.
    public static let domainCompanionApps: [String: String] = [
        "chatgpt.com": "com.openai.chat",
        "claude.ai": "com.anthropic.claudefordesktop",
        "perplexity.ai": "ai.perplexity.mac",
        "copilot.microsoft.com": "com.microsoft.Copilot",
        "grok.com": "ai.x.grok",
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
