import Foundation

public enum TrackingMode: String, Codable, CaseIterable {
    /// Track only sources the user explicitly selected (recommended default).
    case selectedOnly
    /// Track every recognized AI tool found installed on this Mac.
    case allRecognized

    public var displayName: String {
        switch self {
        case .selectedOnly: return "Selected tools only"
        case .allRecognized: return "All recognized AI tools"
        }
    }
}

public enum MenuBarDisplay: String, Codable, CaseIterable {
    case iconOnly
    case iconCompactCount   // e.g. "12.4K"
    case iconRawCount       // e.g. "12,438"
    case iconHiddenCount    // icon only, count intentionally hidden

    public var displayName: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .iconCompactCount: return "Icon + compact count (12.4K)"
        case .iconRawCount: return "Icon + exact count (12,438)"
        case .iconHiddenCount: return "Icon, count hidden"
        }
    }
}

/// Scalar preferences. Sources live in SQLite; these are UserDefaults-backed.
/// UserDefaults is injectable for tests.
public final class AppSettings {
    private let defaults: UserDefaults

    private enum Keys {
        static let trackingMode = "trackingMode"
        static let menuBarDisplay = "menuBarDisplay"
        static let onboardingComplete = "onboardingComplete"
        static let onboardingStep = "onboardingStep"
        static let pausedUntil = "pausedUntil" // unix seconds; -1 = indefinite; absent = active
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var trackingMode: TrackingMode {
        get { TrackingMode(rawValue: defaults.string(forKey: Keys.trackingMode) ?? "") ?? .selectedOnly }
        set { defaults.set(newValue.rawValue, forKey: Keys.trackingMode) }
    }

    public var menuBarDisplay: MenuBarDisplay {
        get { MenuBarDisplay(rawValue: defaults.string(forKey: Keys.menuBarDisplay) ?? "") ?? .iconCompactCount }
        set { defaults.set(newValue.rawValue, forKey: Keys.menuBarDisplay) }
    }

    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Keys.onboardingComplete) }
        set { defaults.set(newValue, forKey: Keys.onboardingComplete) }
    }

    /// Last onboarding step the user was on. Granting Input Monitoring can
    /// require quitting and reopening the app mid-onboarding, and the
    /// permission step promises the flow resumes where it left off.
    public var onboardingStep: Int {
        get { defaults.integer(forKey: Keys.onboardingStep) }
        set { defaults.set(newValue, forKey: Keys.onboardingStep) }
    }

    // MARK: - Pause state

    public enum PauseState: Equatable {
        case active
        case pausedUntil(Int64) // unix seconds
        case pausedIndefinitely
    }

    public func pauseState(now: Int64 = Int64(Date().timeIntervalSince1970)) -> PauseState {
        guard defaults.object(forKey: Keys.pausedUntil) != nil else { return .active }
        let value = Int64(defaults.integer(forKey: Keys.pausedUntil))
        if value < 0 { return .pausedIndefinitely }
        if value > now { return .pausedUntil(value) }
        return .active // expired pause
    }

    public func setPausedUntil(_ until: Int64?) {
        if let until {
            defaults.set(Int(until), forKey: Keys.pausedUntil)
        } else {
            defaults.set(-1, forKey: Keys.pausedUntil)
        }
    }

    public func resume() {
        defaults.removeObject(forKey: Keys.pausedUntil)
    }

    public func isPaused(now: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        pauseState(now: now) != .active
    }
}
