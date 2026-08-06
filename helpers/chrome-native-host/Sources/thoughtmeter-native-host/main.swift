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

/// Other Chrome profiles run their own host against the same file, so a
/// null write must not clobber a fresh tracked state another host produced
/// (HostLogic.shouldWriteState).
var lastWrittenState: ChromeDomainState?

/// Returns whether the state the caller is about to ack is actually visible
/// to the app: written now, or deliberately left to a fresher foreign write.
@discardableResult
func writeState(_ state: ChromeDomainState) -> Bool {
    let current = AtomicFile.readJSON(ChromeDomainState.self, from: DataPaths.chromeStateURL)
    guard HostLogic.shouldWriteState(state, over: current,
                                     lastWrittenByUs: lastWrittenState,
                                     now: nowUnix()) else { return true }
    if (try? AtomicFile.writeJSON(state, to: DataPaths.chromeStateURL)) != nil {
        lastWrittenState = state
        return true
    }
    return false
}

func send(_ outcome: HostLogic.Outcome) {
    guard let payload = try? HostLogic.encodeResponse(outcome) else { return }
    do {
        try stdoutHandle.write(contentsOf: NativeMessageFraming.encode(payload))
    } catch {
        shutdown() // Chrome closed the pipe mid-write — same as EOF.
    }
}

func shutdown() -> Never {
    // Chrome is gone (pipe closed) — make sure the app stops counting Chrome.
    writeState(HostLogic.disconnectState(now: nowUnix()))
    exit(0)
}

// Writing to a pipe Chrome already closed raises SIGPIPE, whose default
// action kills the process BEFORE shutdown() can record the disconnect.
// Ignore it; the throwing write(contentsOf:) in send() handles EPIPE.
signal(SIGPIPE, SIG_IGN)

try? DataPaths.ensureDirectories()

while true {
    let chunk = stdinHandle.availableData
    if chunk.isEmpty { shutdown() }
    buffer.append(chunk)
    guard let messages = NativeMessageFraming.drainMessages(from: &buffer) else {
        shutdown() // protocol violation; fail closed
    }
    for message in messages {
        var outcome = HostLogic.handle(messageData: message, config: configCache.current(), now: nowUnix())
        if let state = outcome.state, !writeState(state) {
            outcome = HostLogic.ackAfterFailedPersist(outcome)
        }
        send(outcome)
    }
}
