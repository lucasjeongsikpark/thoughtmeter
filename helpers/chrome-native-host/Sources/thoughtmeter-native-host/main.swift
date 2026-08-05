import Foundation
import NativeHostCore
import ThoughtMeterKit

/// thoughtmeter-native-host
///
/// Launched by Google Chrome (Native Messaging). Reads framed JSON messages
/// on stdin, writes framed JSON responses on stdout, and maintains
/// `~/Library/Application Support/ThoughtMeter/chrome/state.json` for the
/// ThoughtMeter app. Exits when Chrome closes the pipe.
///
/// This process never opens a network connection and never sees page
/// content — the extension sends hostnames only.

let stdinHandle = FileHandle.standardInput
let stdoutHandle = FileHandle.standardOutput

var buffer = Data()

/// The selected-domain config is written by the app and changes rarely;
/// re-read only when its modification time changes.
final class ConfigCache {
    private var lastModified: Date?
    private var cached: ChromeHostConfig?

    func current() -> ChromeHostConfig? {
        let url = DataPaths.chromeConfigURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if modified != lastModified {
            cached = AtomicFile.readJSON(ChromeHostConfig.self, from: url)
            lastModified = modified
        }
        return cached
    }
}

let configCache = ConfigCache()

func nowUnix() -> Int64 { Int64(Date().timeIntervalSince1970) }

func writeState(_ state: ChromeDomainState) {
    try? AtomicFile.writeJSON(state, to: DataPaths.chromeStateURL)
}

func send(_ outcome: HostLogic.Outcome) {
    guard let payload = try? HostLogic.encodeResponse(outcome) else { return }
    stdoutHandle.write(NativeMessageFraming.encode(payload))
}

func shutdown() -> Never {
    // Chrome is gone (pipe closed) — make sure the app stops counting Chrome.
    writeState(HostLogic.disconnectState(now: nowUnix()))
    exit(0)
}

try? DataPaths.ensureDirectories()

while true {
    let chunk = stdinHandle.availableData
    if chunk.isEmpty { shutdown() } // EOF
    buffer.append(chunk)
    guard let messages = NativeMessageFraming.drainMessages(from: &buffer) else {
        shutdown() // protocol violation; fail closed
    }
    for message in messages {
        let outcome = HostLogic.handle(messageData: message, config: configCache.current(), now: nowUnix())
        if let state = outcome.state { writeState(state) }
        send(outcome)
    }
}
