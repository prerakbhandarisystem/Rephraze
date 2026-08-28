import Foundation

/// Talks to OpenAI's chat completions endpoint, streaming the reply.
///
/// Streaming matters for how this feels: a rewrite takes about a second, and
/// watching words appear reads as fast, while a second of blank waiting reads
/// as broken.
public final class OpenAIClient {

    public enum ClientError: Error, LocalizedError {
        case invalidKey
        case rateLimited
        case serverError(status: Int, body: String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
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

    /// Stream one rewrite in the user's own described voice.
    ///
    /// Deliberately a single call: once someone has told us how they want to
    /// sound, offering four alternatives is asking a question they already
    /// answered.
    public func rephrasePersonal(
        text: String,
        style: String,
        model: String = Settings.model,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(
                        messages: Self.rewriteMessages(
                            system: Prompt.personalSystem(style: style), text: text
                        ),
                        model: model,
                        apiKey: apiKey,
                        temperature: 0.4,
                        maxTokens: Self.tokenBudget(for: text),
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

    // MARK: - Four variants

    /// Ask for all four rewrites in a single structured response.
    public func rephraseVariants(
        text: String,
        model: String = Settings.model,
        apiKey: String
    ) async throws -> RephraseSet {

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45

        let body: [String: Any] = [
            "model": model,
            // Low but not zero: rewriting wants a little freedom, not invention.
            "temperature": 0.5,
            // Guarantees parseable output instead of hoping the model behaves.
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Prompt.variantsSystem],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            switch http.statusCode {
            case 401: throw ClientError.invalidKey
            case 429: throw ClientError.rateLimited
            default: throw ClientError.serverError(status: http.statusCode, body: bodyText)
            }
        }

        guard let content = Self.extractMessageContent(data) else {
            throw ClientError.emptyResponse
        }

        let variants = Self.parseVariants(content)
        guard !variants.isEmpty else { throw ClientError.emptyResponse }

        return RephraseSet(original: text, variants: variants)
    }

    /// Pull `choices[0].message.content` out of a non-streamed response.
    static func extractMessageContent(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }

    /// Turn the model's JSON into variants, keeping whatever is usable.
    ///
    /// Tolerant on purpose: a missing key should cost one option, not the whole
    /// panel.
    static func parseVariants(_ content: String) -> [RephraseVariant: String] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var result: [RephraseVariant: String] = [:]
        for variant in RephraseVariant.allCases {
            if let value = object[variant.rawValue] as? String {
                let cleaned = RewriteSanitizer.clean(value)
                if !cleaned.isEmpty { result[variant] = cleaned }
            }
        }
        return result
    }

    // MARK: - Four variants, in parallel

    /// What the parallel path reports back as it goes.
    public enum VariantEvent: Sendable {
        /// More text for one variant. Arrives while it is still being written.
        case delta(RephraseVariant, String)
        /// That variant is complete.
        case finished(RephraseVariant)
        /// That variant alone failed. The other three are unaffected.
        case failed(RephraseVariant, String)
    }

    /// Ask for the four rewrites as four concurrent streamed calls.
    ///
    /// Slower in total tokens, faster in every way the user can perceive: the
    /// single-call path writes all four variants into one response serially, so
    /// nothing can be shown until the last one lands. Here each variant streams
    /// into its own card, and wall-clock time is the slowest single rewrite
    /// rather than the sum of four.
    ///
    /// One variant failing is survivable and reported per variant -- the panel
    /// keeps the rest.
    public func rephraseVariantsStreaming(
        text: String,
        model: String = Settings.model,
        apiKey: String
    ) -> AsyncStream<VariantEvent> {

        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for variant in RephraseVariant.allCases {
                        group.addTask {
                            do {
                                try await self.run(
                                    messages: Self.rewriteMessages(
                                        system: Prompt.singleVariantSystem(for: variant),
                                        text: text
                                    ),
                                    model: model,
                                    apiKey: apiKey,
                                    temperature: 0.5,
                                    maxTokens: Self.tokenBudget(for: text),
                                    onDelta: { continuation.yield(.delta(variant, $0)) }
                                )
                                continuation.yield(.finished(variant))
                            } catch is CancellationError {
                                // Panel dismissed. Say nothing.
                            } catch {
                                continuation.yield(
                                    .failed(variant, error.localizedDescription)
                                )
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Refining, in conversation

    /// Stream the next rewrite in a follow-up conversation.
    ///
    /// The whole exchange goes up each time rather than just the newest
    /// instruction -- see `Conversation` for why that is the difference between
    /// a conversation and four unrelated rewrites.
    ///
    /// The budget is sized against the original, not the transcript: however
    /// long the conversation gets, the reply is still one rewrite of one piece
    /// of text.
    public func refine(
        conversation: Conversation,
        style: String,
        model: String = Settings.model,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(
                        messages: conversation.messages(
                            system: Prompt.chatSystem(style: style)
                        ),
                        model: model,
                        apiKey: apiKey,
                        temperature: 0.4,
                        maxTokens: Self.tokenBudget(for: conversation.original),
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

    // MARK: - Translation

    /// Stream the message written in another language.
    ///
    /// One call, not two. The translation is composed straight from what the
    /// user wrote -- see `Prompt.translateSystem` for why routing it through a
    /// cleaned-up English draft first would be both slower and worse.
    ///
    /// Single result rather than four, for the same reason as the personal
    /// path: the user has already answered the only question by picking a
    /// language, so there is nothing left to choose between.
    public func translate(
        text: String,
        to language: TargetLanguage,
        model: String = Settings.model,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(
                        messages: Self.rewriteMessages(
                            system: Prompt.translateSystem(to: language), text: text
                        ),
                        model: model,
                        apiKey: apiKey,
                        temperature: 0.4,
                        maxTokens: Self.translationBudget(for: text),
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

    /// Ceiling on completion length, scaled to the input.
    ///
    /// Generous on purpose -- this is a runaway guard, not a length control.
    /// Cutting a rewrite off mid-sentence would be worse than a slow one.
    static func tokenBudget(for text: String) -> Int {
        let approxInputTokens = max(1, text.count / 4)
        return min(4096, max(256, approxInputTokens * 3))
    }

    /// Ceiling for a translation, which needs more room than a rewrite.
    ///
    /// `tokenBudget` assumes the output is roughly the size of the input, which
    /// holds while both are the same language and breaks badly when they are
    /// not. The same sentence costs several times more tokens in Hindi or
    /// Japanese than in English, because the tokenizer was not built for those
    /// scripts -- so the rewrite budget would cut a perfectly good translation
    /// off mid-sentence. This is a runaway guard rather than a length control,
    /// and a model that stops on its own never spends the headroom.
    static func translationBudget(for text: String) -> Int {
        min(4096, tokenBudget(for: text) * 2)
    }

    /// The usual two-message shape: how to rewrite, then what to rewrite.
    private static func rewriteMessages(system: String, text: String) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: text),
        ]
    }

    private func run(
        messages: [ChatMessage],
        model: String,
        apiKey: String,
        temperature: Double,
        maxTokens: Int,
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
            "temperature": temperature,
            // A rewrite is never much longer than its input. Without a cap, one
            // confused response can run for thousands of tokens while the user
            // watches a spinner.
            "max_tokens": maxTokens,
            "messages": messages.map(\.payload),
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
