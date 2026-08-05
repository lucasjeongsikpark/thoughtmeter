import Foundation

/// Chrome Native Messaging wire format: each message is a 32-bit
/// little-endian length prefix followed by that many bytes of UTF-8 JSON.
public enum NativeMessageFraming {
    /// Chrome limits host→browser messages to 1 MB; ours are tiny.
    /// Anything larger than this is a protocol violation — drop the stream.
    public static let maxMessageSize = 1 << 20

    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    /// Extract complete messages from an accumulating buffer.
    /// Consumed bytes are removed from `buffer`; a partial trailing frame
    /// stays in place for the next read. Returns nil on protocol violation.
    public static func drainMessages(from buffer: inout Data) -> [Data]? {
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
            guard length <= maxMessageSize else { return nil }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            messages.append(buffer.subdata(in: 4..<total))
            buffer.removeSubrange(0..<total)
        }
        return messages
    }
}
