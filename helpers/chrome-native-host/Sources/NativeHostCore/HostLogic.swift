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

    public static func encodeResponse(_ outcome: Outcome) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(outcome.response)
    }
}
