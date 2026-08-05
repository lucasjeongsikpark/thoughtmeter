import Foundation
import ThoughtMeterKit

/// Each test gets a throwaway UserDefaults suite whose persistent domain is
/// removed afterward — the setters write a real plist into
/// ~/Library/Preferences, and without the cleanup every run leaks one file
/// per test forever.
private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "thoughtmeter-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer {
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        // cfprefsd leaves an empty plist behind even after the domain is
        // removed — unlink it so runs leave no trace.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }
    try body(defaults)
}

let settingsTests: [TC] = [
    TC("defaults: selected-only mode, compact menu bar, onboarding incomplete") { t in
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            t.expectEqual(settings.trackingMode, .selectedOnly)
            t.expectEqual(settings.menuBarDisplay, .iconCompactCount)
            t.expect(!settings.onboardingComplete)
            t.expectEqual(settings.pauseState(now: 100), .active)
        }
    },
    TC("pause until a time expires on its own") { t in
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setPausedUntil(1000)
            t.expectEqual(settings.pauseState(now: 500), .pausedUntil(1000))
            t.expect(settings.isPaused(now: 500))
            t.expectEqual(settings.pauseState(now: 1001), .active, "expired pause auto-resumes")
        }
    },
    TC("indefinite pause persists until resume") { t in
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.setPausedUntil(nil)
            t.expectEqual(settings.pauseState(now: 1_000_000_000), .pausedIndefinitely)
            settings.resume()
            t.expectEqual(settings.pauseState(now: 1_000_000_000), .active)
        }
    },
    TC("mode and display round trip") { t in
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.trackingMode = .allRecognized
            settings.menuBarDisplay = .iconRawCount
            t.expectEqual(settings.trackingMode, .allRecognized)
            t.expectEqual(settings.menuBarDisplay, .iconRawCount)
        }
    },
    TC("onboarding step defaults to the first step and round trips") { t in
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            t.expectEqual(settings.onboardingStep, 0, "fresh install starts at step 0")
            settings.onboardingStep = 2
            t.expectEqual(settings.onboardingStep, 2, "a quit-and-reopen must resume mid-flow")
        }
    },
]

let formatterTests: [TC] = [
    TC("compact formatting") { t in
        t.expectEqual(CountFormatter.compact(0), "0")
        t.expectEqual(CountFormatter.compact(982), "982")
        t.expectEqual(CountFormatter.compact(1000), "1K")
        t.expectEqual(CountFormatter.compact(12_438), "12.4K")
        t.expectEqual(CountFormatter.compact(999_949), "999.9K")
        t.expectEqual(CountFormatter.compact(999_950), "1M", "rounding past the K range promotes the unit, never \"1000K\"")
        t.expectEqual(CountFormatter.compact(999_999), "1M")
        t.expectEqual(CountFormatter.compact(2_400_000), "2.4M")
    },
    TC("exact formatting") { t in
        t.expectEqual(CountFormatter.exact(12_438), "12,438")
        t.expectEqual(CountFormatter.exact(0), "0")
    },
]

let localDateTests: [TC] = [
    TC("local date string respects timezone") { t in
        let utc = LocalDateProvider(timeZone: TimeZone(identifier: "UTC")!)
        let tokyo = LocalDateProvider(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        // 2026-08-04 20:00 UTC = 2026-08-05 05:00 Tokyo
        let evening: Int64 = 1_785_873_600
        t.expectEqual(utc.localDateString(forUnixSeconds: evening), "2026-08-04")
        t.expectEqual(tokyo.localDateString(forUnixSeconds: evening), "2026-08-05")
    },
    TC("recent local dates are consecutive and end today") { t in
        let utc = LocalDateProvider(timeZone: TimeZone(identifier: "UTC")!)
        let now: Int64 = 1_785_873_600 // 2026-08-04 UTC
        let dates = utc.recentLocalDates(count: 7, now: now)
        t.expectEqual(dates.count, 7)
        t.expectEqual(dates.last, "2026-08-04")
        t.expectEqual(dates.first, "2026-07-29")
    },
    TC("start of tomorrow is a local midnight after now") { t in
        let utc = LocalDateProvider(timeZone: TimeZone(identifier: "UTC")!)
        let now: Int64 = 1_785_873_600 // 2026-08-04 20:00 UTC
        let tomorrow = utc.startOfTomorrow(now: now)
        t.expect(tomorrow > now)
        t.expectEqual(utc.localDateString(forUnixSeconds: tomorrow), "2026-08-05")
        t.expectEqual(tomorrow % 86_400, 0, "UTC midnight is day aligned")
    },
]
