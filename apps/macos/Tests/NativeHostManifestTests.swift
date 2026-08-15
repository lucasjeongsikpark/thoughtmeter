import Foundation
import ThoughtMeterKit

private let storeID = "omhnbpfiapchifodmobgeglhgpgolmhn"
private let devID = "abcdefghijklmnopabcdefghijklmnop"
private let storeOrigin = "chrome-extension://\(storeID)/"
private let installedHost = "/Applications/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host"

private func expectOriginError(
    _ t: T,
    _ expected: NativeHostManifest.OriginError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> [String]
) {
    do {
        let origins = try body()
        t.fail("expected \(expected), got origins \(origins)", file: file, line: line)
    } catch let error as NativeHostManifest.OriginError {
        t.expectEqual(error, expected, file: file, line: line)
    } catch {
        t.fail("expected \(expected), got \(error)", file: file, line: line)
    }
}

let nativeHostManifestTests: [TC] = [
    TC("production ID alone yields exactly the store origin") { t in
        let origins = try NativeHostManifest.origins(production: storeID, development: nil)
        t.expectEqual(origins, ["chrome-extension://\(storeID)/"])
    },
    TC("production comes before development") { t in
        let origins = try NativeHostManifest.origins(production: storeID, development: devID)
        t.expectEqual(origins, [
            "chrome-extension://\(storeID)/",
            "chrome-extension://\(devID)/",
        ])
    },
    TC("the same ID in both slots is not duplicated") { t in
        let origins = try NativeHostManifest.origins(production: storeID, development: storeID)
        t.expectEqual(origins, ["chrome-extension://\(storeID)/"])
    },
    TC("a malformed production ID throws instead of being dropped") { t in
        // Dropping it silently would ship a release whose only symptom is
        // "Not connected", with nothing naming release-config.sh as the cause.
        expectOriginError(t, .invalidProductionExtensionID("omhnbpfiapchifodmobgeglhgpgolmh")) {
            try NativeHostManifest.origins(production: "omhnbpfiapchifodmobgeglhgpgolmh", development: nil)
        }
    },
    TC("a production ID outside the a–p alphabet throws") { t in
        let bad = "omhnbpfiapchifodmobgeglhgpgolmhz"
        expectOriginError(t, .invalidProductionExtensionID(bad)) {
            try NativeHostManifest.origins(production: bad, development: devID)
        }
    },
    TC("UNSET and empty production IDs are absent, not invalid") { t in
        let unset = try NativeHostManifest.origins(production: "UNSET", development: devID)
        t.expectEqual(unset, ["chrome-extension://\(devID)/"])
        let empty = try NativeHostManifest.origins(production: "", development: devID)
        t.expectEqual(empty, ["chrome-extension://\(devID)/"])
    },
    TC("a malformed development ID is filtered, leaving the store origin intact") { t in
        // Opposite of the production rule: a stale value saved before the
        // Settings-entry check existed must self-heal, not wedge the install.
        let origins = try NativeHostManifest.origins(production: storeID, development: "not a real id\n")
        t.expectEqual(origins, ["chrome-extension://\(storeID)/"])
    },
    TC("no usable ID at all throws noExtensionID") { t in
        expectOriginError(t, .noExtensionID) {
            try NativeHostManifest.origins(production: "UNSET", development: "garbage")
        }
    },
    TC("an up-to-date manifest is left alone") { t in
        let state = NativeHostManifest.InstalledState.present(
            .init(path: installedHost, origins: [storeOrigin])
        )
        t.expect(
            !NativeHostManifest.repairIsNeeded(
                state, expectedPath: installedHost, expectedOrigins: [storeOrigin],
                installedPathExists: true
            ),
            "no repair when nothing drifted"
        )
    },
    TC("a moved app leaves a dead path behind, which IS repaired") { t in
        let state = NativeHostManifest.InstalledState.present(
            .init(path: "/Users/someone/Downloads/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host",
                  origins: [storeOrigin])
        )
        t.expect(
            NativeHostManifest.repairIsNeeded(
                state, expectedPath: installedHost, expectedOrigins: [storeOrigin],
                installedPathExists: false
            ),
            "a path whose binary is gone is taken over"
        )
    },
    TC("a live registration owned by another copy is NOT hijacked") { t in
        // A debug build launched from .build/dev must not repoint Chrome at
        // itself: the two copies would trade the registration on every launch,
        // and the installed copy is the one the user actually runs.
        let state = NativeHostManifest.InstalledState.present(
            .init(path: installedHost, origins: [storeOrigin])
        )
        t.expect(
            !NativeHostManifest.repairIsNeeded(
                state,
                expectedPath: "/Users/dev/repo/.build/dev/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host",
                expectedOrigins: [storeOrigin],
                installedPathExists: true
            ),
            "a working registration is left to its owner"
        )
    },
    TC("origin drift is repaired for the copy that owns the registration") { t in
        let state = NativeHostManifest.InstalledState.present(
            .init(path: installedHost, origins: ["chrome-extension://\(devID)/"])
        )
        t.expect(
            NativeHostManifest.repairIsNeeded(
                state, expectedPath: installedHost, expectedOrigins: [storeOrigin],
                installedPathExists: true
            ),
            "origin drift is repaired"
        )
    },
    TC("another copy's origins are NOT rewritten, even when they differ") { t in
        // The dangerous shape: a bare `swift run ThoughtMeter` has no bundle,
        // so it computes no production extension ID. If origin drift alone
        // triggered repair it would strip the Web Store origin from a working
        // /Applications registration.
        let state = NativeHostManifest.InstalledState.present(
            .init(path: installedHost,
                  origins: [storeOrigin, "chrome-extension://\(devID)/"])
        )
        t.expect(
            !NativeHostManifest.repairIsNeeded(
                state,
                expectedPath: "/Users/dev/repo/.build/debug/thoughtmeter-native-host",
                expectedOrigins: ["chrome-extension://\(devID)/"],
                installedPathExists: true
            ),
            "a live registration owned by another copy is untouched, origins included"
        )
    },
    TC("an absent manifest is NOT installed behind the user's back") { t in
        // Registering a native messaging host is a deliberate setup step. A
        // user who never enabled Chrome must not get one at startup.
        t.expect(
            !NativeHostManifest.repairIsNeeded(
                .absent, expectedPath: installedHost, expectedOrigins: [storeOrigin],
                installedPathExists: false
            ),
            "absent means leave it absent"
        )
    },
    TC("an unreadable manifest is rewritten") { t in
        t.expect(
            NativeHostManifest.repairIsNeeded(
                .unreadable, expectedPath: installedHost, expectedOrigins: [storeOrigin],
                installedPathExists: false
            ),
            "a broken manifest is worse than a rewritten one"
        )
    },
    TC("decoding recognizes valid, malformed, and truncated manifests") { t in
        let valid = Data("""
            {"name":"org.thoughtmeter.chromehost","path":"/Applications/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host","type":"stdio","allowed_origins":["chrome-extension://\(storeID)/"]}
            """.utf8)
        t.expectEqual(
            NativeHostManifest.decodeInstalled(valid),
            .present(.init(path: "/Applications/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host",
                           origins: ["chrome-extension://\(storeID)/"]))
        )
        t.expectEqual(NativeHostManifest.decodeInstalled(Data("{ not json".utf8)), .unreadable)
        // Valid JSON, but missing the keys the repair check compares.
        t.expectEqual(NativeHostManifest.decodeInstalled(Data(#"{"name":"x"}"#.utf8)), .unreadable)
    },
    TC("host name matches the manifest filename the app installs and removes") { t in
        t.expectEqual(NativeHostManifest.hostName, "org.thoughtmeter.chromehost")
        t.expect(
            DataPaths.chromeNativeMessagingManifestURL.lastPathComponent
                == "\(NativeHostManifest.hostName).json",
            "manifest filename is derived from hostName"
        )
    },
]
