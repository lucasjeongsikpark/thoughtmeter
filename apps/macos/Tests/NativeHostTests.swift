import Foundation
import NativeHostCore
import ThoughtMeterKit

private func stateMessage(_ host: String?) -> Data {
    let object: [String: Any] = host.map { ["type": "state", "host": $0] } ?? ["type": "state", "host": NSNull()]
    return try! JSONSerialization.data(withJSONObject: object)
}

private let testConfig = ChromeHostConfig(domains: ["chatgpt.com", "claude.ai"], updatedAt: 0)

let framingTests: [TC] = [
    TC("encode/drain round trip") { t in
        let payload = Data(#"{"type":"ping"}"#.utf8)
        var buffer = NativeMessageFraming.encode(payload)
        let messages = NativeMessageFraming.drainMessages(from: &buffer)
        t.expectEqual(messages?.count, 1)
        t.expectEqual(messages?.first, payload)
        t.expect(buffer.isEmpty, "buffer fully consumed")
    },
    TC("partial frame stays buffered") { t in
        let payload = Data(#"{"type":"ping"}"#.utf8)
        let framed = NativeMessageFraming.encode(payload)
        var buffer = framed.prefix(6) // header + 2 bytes
        let messages = NativeMessageFraming.drainMessages(from: &buffer)
        t.expectEqual(messages?.count, 0)
        t.expectEqual(buffer.count, 6, "partial bytes retained")
    },
    TC("two frames in one chunk") { t in
        let a = Data(#"{"a":1}"#.utf8)
        let b = Data(#"{"b":2}"#.utf8)
        var buffer = NativeMessageFraming.encode(a) + NativeMessageFraming.encode(b)
        let messages = NativeMessageFraming.drainMessages(from: &buffer)
        t.expectEqual(messages?.count, 2)
    },
    TC("oversized frame is a protocol violation") { t in
        var length = UInt32(NativeMessageFraming.maxMessageSize + 1).littleEndian
        var buffer = Data(bytes: &length, count: 4)
        buffer.append(Data(repeating: 0, count: 8))
        t.expectNil(NativeMessageFraming.drainMessages(from: &buffer))
    },
]

let hostLogicTests: [TC] = [
    TC("selected domain is tracked and canonicalized") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("claude.ai"), config: testConfig, now: 500)
        t.expectEqual(outcome.state, ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 500))
        t.expectEqual(outcome.response["tracked"], .bool(true))
    },
    TC("subdomain of selected domain canonicalizes to selected domain") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("chat.claude.ai"), config: testConfig, now: 500)
        t.expectEqual(outcome.state?.trackedDomain, "claude.ai")
    },
    TC("www variant of selected domain is tracked") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("www.chatgpt.com"), config: testConfig, now: 500)
        t.expectEqual(outcome.state?.trackedDomain, "chatgpt.com")
    },
    TC("non-selected domain writes null state (never the hostname)") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("secret-site.example.com"), config: testConfig, now: 500)
        t.expectEqual(outcome.state, ChromeDomainState(trackedDomain: nil, updatedAt: 500))
        t.expectEqual(outcome.response["tracked"], .bool(false))
        if let data = try? HostLogic.encodeResponse(outcome) {
            let text = String(decoding: data, as: UTF8.self)
            t.expect(!text.contains("secret-site"), "non-selected hostname must not appear in the ack")
        }
    },
    TC("null host writes null state") { t in
        let outcome = HostLogic.handle(messageData: stateMessage(nil), config: testConfig, now: 500)
        t.expectEqual(outcome.state, ChromeDomainState(trackedDomain: nil, updatedAt: 500))
    },
    TC("invalid hostname writes null state") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("not a host!!"), config: testConfig, now: 500)
        t.expectEqual(outcome.state, ChromeDomainState(trackedDomain: nil, updatedAt: 500))
    },
    TC("missing config means nothing is tracked") { t in
        let outcome = HostLogic.handle(messageData: stateMessage("claude.ai"), config: nil, now: 500)
        t.expectEqual(outcome.state, ChromeDomainState(trackedDomain: nil, updatedAt: 500))
    },
    TC("ping produces pong and no state change") { t in
        let outcome = HostLogic.handle(messageData: Data(#"{"type":"ping"}"#.utf8), config: testConfig, now: 500)
        t.expectNil(outcome.state)
        t.expectEqual(outcome.response["type"], .string("pong"))
    },
    TC("malformed message is an error, no state change") { t in
        let outcome = HostLogic.handle(messageData: Data("garbage".utf8), config: testConfig, now: 500)
        t.expectNil(outcome.state)
        t.expectEqual(outcome.response["type"], .string("error"))
    },
    TC("disconnect state is null") { t in
        let state = HostLogic.disconnectState(now: 900)
        t.expectEqual(state, ChromeDomainState(trackedDomain: nil, updatedAt: 900))
    },
]

let atomicFileTests: [TC] = [
    TC("atomic JSON write/read round trip with 0600 permissions") { t in
        try withTempDirectory { dir in
            let url = dir.appendingPathComponent("nested/state.json")
            let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 42)
            try AtomicFile.writeJSON(state, to: url)
            t.expectEqual(AtomicFile.readJSON(ChromeDomainState.self, from: url), state)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0
            t.expectEqual(permissions & 0o777, 0o600)
        }
    },
    TC("overwrite replaces content atomically") { t in
        try withTempDirectory { dir in
            let url = dir.appendingPathComponent("state.json")
            try AtomicFile.writeJSON(ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 1), to: url)
            try AtomicFile.writeJSON(ChromeDomainState(trackedDomain: nil, updatedAt: 2), to: url)
            let read = AtomicFile.readJSON(ChromeDomainState.self, from: url)
            t.expectEqual(read, ChromeDomainState(trackedDomain: nil, updatedAt: 2))
        }
    },
    TC("corrupt state file reads as nil") { t in
        try withTempDirectory { dir in
            let url = dir.appendingPathComponent("state.json")
            try Data("not json".utf8).write(to: url)
            t.expectNil(AtomicFile.readJSON(ChromeDomainState.self, from: url))
        }
    },
]
