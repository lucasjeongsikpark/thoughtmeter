import Foundation
import ThoughtMeterKit

/// Pure decision logic for the native messaging host, separated from I/O so
/// it can be tested directly.
///
/// Privacy invariant: the ONLY value ever written to disk is a domain the
/// user selected in the ThoughtMeter app (canonical form) or nil. Hostnames
/// of other sites exist here only in memory, for matching.
public enum HostLogic {
    public struct IncomingMessage: Decodable {
        public let type: String
        public let host: String?
    }

    public struct Outcome: Equatable {
        /// JSON-encodable response to send back to the extension.
        public let response: [String: AnyHashableJSON]
        /// State to persist for the app, if this message changes it.
        public let state: ChromeDomainState?
    }

    /// Minimal JSON value wrapper so Outcome stays Equatable without
    /// bringing in a JSON library.
    public enum AnyHashableJSON: Equatable, Encodable {
        case string(String)
        case bool(Bool)
        case null

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

    public static let protocolVersion = "1"

    public static func handle(messageData: Data, config: ChromeHostConfig?, now: Int64) -> Outcome {
        guard let message = try? JSONDecoder().decode(IncomingMessage.self, from: messageData) else {
            return Outcome(response: ["type": .string("error"), "reason": .string("malformed message")], state: nil)
        }
        switch message.type {
        case "ping":
            return Outcome(
                response: ["type": .string("pong"), "version": .string(protocolVersion)],
                state: nil
            )
        case "state":
            let selectedDomains = config?.domains ?? []
            var tracked: String? = nil
            if let rawHost = message.host,
               let normalized = DomainNormalizer.normalize(rawHost) {
                tracked = DomainNormalizer.canonicalSelectedDomain(forHost: normalized, in: selectedDomains)
            }
            let state = ChromeDomainState(trackedDomain: tracked, updatedAt: now)
            return Outcome(
                response: [
                    "type": .string("stateAck"),
                    "tracked": .bool(tracked != nil),
                    "trackedDomain": tracked.map { .string($0) } ?? .null,
                ],
                state: state
            )
        default:
            return Outcome(response: ["type": .string("error"), "reason": .string("unknown type")], state: nil)
        }
    }

    /// State written when the extension disconnects (Chrome quit, extension
    /// disabled): explicit null so the app immediately stops counting Chrome.
    public static func disconnectState(now: Int64) -> ChromeDomainState {
        ChromeDomainState(trackedDomain: nil, updatedAt: now)
    }

    /// Whether a state write may proceed. Each Chrome profile with the
    /// extension spawns its OWN host process, and all of them share one
    /// state file: without this gate, an unfocused profile's keepalive null
    /// (or its disconnect write when its service worker suspends) clobbers
    /// the focused profile's fresh tracked state once a minute, silently
    /// stopping Chrome counting for most of every minute.
    ///
    /// Rules: a tracked (non-nil) write always wins. A null write proceeds
    /// unless the file currently holds a fresh tracked state that some
    /// OTHER writer produced (current != our own last write). With a single
    /// profile the file always matches our last write, so disconnect/EOF
    /// semantics are unchanged.
    public static func shouldWriteState(_ new: ChromeDomainState,
                                        over current: ChromeDomainState?,
                                        lastWrittenByUs: ChromeDomainState?,
                                        now: Int64) -> Bool {
        if new.trackedDomain != nil { return true }
        guard let current, current.trackedDomain != nil, current.isFresh(now: now) else {
            return true
        }
        return current == lastWrittenByUs
    }

    /// The app reads state.json, not this ack — so a state the host failed
    /// to persist is a chain the app cannot see, and the popup must not
    /// render it as "Tracked: Yes" while nothing counts. The connection
    /// itself is still real (the host is alive and answering), so only the
    /// tracked claim is withdrawn.
    public static func ackAfterFailedPersist(_ outcome: Outcome) -> Outcome {
        guard outcome.response["type"] == .string("stateAck") else { return outcome }
        var response = outcome.response
        response["tracked"] = .bool(false)
        response["trackedDomain"] = .null
        return Outcome(response: response, state: outcome.state)
    }

    public static func encodeResponse(_ outcome: Outcome) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(outcome.response)
    }
}
