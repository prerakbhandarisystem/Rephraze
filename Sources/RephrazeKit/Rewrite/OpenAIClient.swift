import Foundation

/// Talks to OpenAI's chat completions endpoint, streaming the reply.
///
/// Streaming matters for how this feels: a rewrite takes about a second, and
/// watching words appear reads as fast, while a second of blank waiting reads
/// as broken.
public final class OpenAIClient {

    public enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case invalidKey
        case rateLimited
        case serverError(status: Int, body: String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No API key. Add one in Rephraze settings."
            case .invalidKey:
                return "That API key was rejected. Check it in settings."
            case .rateLimited:
                return "OpenAI is rate limiting. Try again in a moment."
            case let .serverError(status, body):
                let detail = body.isEmpty ? "" : " — \(body.prefix(200))"
                return "OpenAI returned \(status)\(detail)"
            case .emptyResponse:
                return "OpenAI returned nothing."
            }
        }
    }

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Stream a rewrite, yielding text as it arrives.
    public func rephrase(
        text: String,
        model: String = Settings.model,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(
                        text: text,
                        model: model,
                        apiKey: apiKey,
                        onDelta: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        text: String,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) -> Void
    ) async throws {

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            // Low but not zero: rephrasing wants a little freedom, not invention.
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": Prompt.system],
                ["role": "user", "content": Prompt.user(text)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            switch http.statusCode {
            case 401: throw ClientError.invalidKey
            case 429: throw ClientError.rateLimited
            default: throw ClientError.serverError(status: http.statusCode, body: errorBody)
            }
        }

        // URLSession already splits the stream into lines for us, and does it
        // without allocating per byte.
        let parser = SSEParser()
        var produced = false

        for try await line in bytes.lines {
            guard let event = parser.parse(line: line) else { continue }
            switch event {
            case .done:
                guard produced else { throw ClientError.emptyResponse }
                return
            case let .data(payload):
                if let delta = Self.extractDelta(payload), !delta.isEmpty {
                    produced = true
                    onDelta(delta)
                }
            }
        }

        guard produced else { throw ClientError.emptyResponse }
    }

    /// Pull `choices[0].delta.content` out of one streamed JSON chunk.
    static func extractDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else {
            return nil
        }
        return content
    }
}
