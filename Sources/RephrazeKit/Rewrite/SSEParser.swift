import Foundation

/// Parses Server-Sent Events out of a byte stream.
///
/// The network hands us arbitrary chunks, not tidy lines. A single chunk can
/// end mid-word, mid-line, or even mid-UTF8-character, and one line can arrive
/// split across three chunks. So we buffer bytes and only emit complete lines.
///
/// Kept free of URLSession so it can be tested by feeding it deliberately ugly
/// chunk boundaries.
public struct SSEParser {

    public enum Event: Equatable {
        /// A `data:` payload, with the prefix stripped.
        case data(String)
        /// The stream said it is finished.
        case done
    }

    private var buffer = Data()

    public init() {}

    /// Feed a chunk, get back whatever complete events it completed.
    public mutating func consume(_ chunk: Data) -> [Event] {
        buffer.append(chunk)
        var events: [Event] = []

        // 0x0A is "\n". SSE lines are newline delimited; a blank line separates
        // events, which we do not need to track since each event is one line.
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            if let event = parse(line: line) {
                events.append(event)
            }
        }

        return events
    }

    /// Flush anything left when the connection closes without a trailing newline.
    public mutating func finish() -> [Event] {
        guard !buffer.isEmpty,
              let line = String(data: buffer, encoding: .utf8)
        else {
            buffer.removeAll()
            return []
        }
        buffer.removeAll()
        return parse(line: line).map { [$0] } ?? []
    }

    /// Parse one complete line. Exposed because URLSession can already split
    /// a stream into lines efficiently -- the byte buffering above is only
    /// needed for transports that cannot.
    public func parse(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Blank lines separate events; comments start with ":".
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { return .done }
        guard !payload.isEmpty else { return nil }
        return .data(payload)
    }
}
