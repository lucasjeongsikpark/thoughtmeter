import Foundation
import ThoughtMeterKit

let chromeReaderTests: [TC] = [
    TC("reader picks up state file changes via directory watch") { t in
        try withTempDirectory { dir in
            let stateURL = dir.appendingPathComponent("state.json")
            let reader = ChromeStateReader(stateURL: stateURL)
            let semaphore = DispatchSemaphore(value: 0)
            var seen: [ChromeDomainState?] = []
            let lock = NSLock()
            reader.onChange = { state in
                lock.lock(); seen.append(state); lock.unlock()
                semaphore.signal()
            }
            reader.start()
            // Give the watcher a moment to install, then write like the host does.
            Thread.sleep(forTimeInterval: 0.2)
            try AtomicFile.writeJSON(ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 10), to: stateURL)
            t.expect(semaphore.wait(timeout: .now() + 3) == .success, "change notification within 3s")
            t.expectEqual(reader.currentState?.trackedDomain, "claude.ai")

            try AtomicFile.writeJSON(ChromeDomainState(trackedDomain: nil, updatedAt: 20), to: stateURL)
            t.expect(semaphore.wait(timeout: .now() + 3) == .success, "second change notification")
            t.expectEqual(reader.currentState, ChromeDomainState(trackedDomain: nil, updatedAt: 20))
            reader.stop()
        }
    },
    TC("missing state file reads as nil (Chrome input not counted)") { t in
        try withTempDirectory { dir in
            let reader = ChromeStateReader(stateURL: dir.appendingPathComponent("absent.json"))
            reader.start()
            Thread.sleep(forTimeInterval: 0.2)
            t.expectNil(reader.currentState)
            reader.stop()
        }
    },
    TC("config writer produces sorted normalized config") { t in
        try withTempDirectory { dir in
            let url = dir.appendingPathComponent("config.json")
            try ChromeConfigWriter.write(domains: ["claude.ai", "chatgpt.com"], to: url, now: 77)
            let config = AtomicFile.readJSON(ChromeHostConfig.self, from: url)
            t.expectEqual(config, ChromeHostConfig(domains: ["chatgpt.com", "claude.ai"], updatedAt: 77))
        }
    },
]
