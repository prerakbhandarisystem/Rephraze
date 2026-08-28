import Foundation

/// Posts a support report and waits to hear that it was actually sent.
///
/// The endpoint on the other end holds the mail service credential and does
/// the sending, so this is the whole of the client: one POST, one answer, and
/// no retry. A support form is a person watching a button — if it did not work
/// they should be told now, while they still have what they wrote in front of
/// them, not have it quietly retried behind their back.
public struct TicketSender {

    /// Why a report did not go, in words that can be shown to whoever wrote it.
    ///
    /// Every case ends up on screen, so none of them is a status code: what a
    /// sender needs to know is whether to try again, fix something, or send it
    /// another way.
    public enum Failure: Error, LocalizedError, Equatable {
        /// This build has no endpoint, so there was never anywhere to post to.
        case nowhereToSend
        /// The request never arrived — no network, or the server is down.
        case unreachable
        /// The server understood the report and would not take it.
        case refused(String)
        /// The server took it and could not get it sent.
        case notDelivered

        public var errorDescription: String? {
            switch self {
            case .nowhereToSend:
                return "This build has nowhere to send reports."
            case .unreachable:
                return "Could not reach the support server — check your connection."
            case let .refused(reason):
                return reason
            case .notDelivered:
                return "The support server could not send it just now."
            }
        }
    }

    /// How the request travels. Exactly `URLSession.data(for:)`, so the real
    /// one is a one-liner and a test can answer with a status code of its own
    /// without a network or a server.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoint: URL?
    private let transport: Transport

    public init(
        endpoint: URL? = AppInfo.supportEndpoint,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// True when this build can send a report itself. When it cannot, the
    /// Support section says so and hands the report to the mail client rather
    /// than offering a button that goes nowhere.
    public var canSend: Bool { endpoint != nil }

    /// Send one report. Returns when it has been accepted for delivery; throws
    /// a `Failure` otherwise.
    ///
    /// The server waits for the mail service before it answers, so this can
    /// take a few seconds. That wait is the point — it is what makes "Sent"
    /// on screen true.
    public func send(_ ticket: SupportTicket) async throws {
        guard let endpoint else { throw Failure.nowhereToSend }
        guard let payload = ticket.payload else { throw Failure.refused("That report could not be packed up.") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long enough to cover the server's own wait on the mail service, and
        // short enough that a hung connection does not hold the button down
        // forever.
        request.timeoutInterval = 30
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw Failure.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.notDelivered }
        guard !(200..<300).contains(http.statusCode) else { return }

        // The server's own wording for anything it refuses outright. It writes
        // those messages for this screen, so they are shown as they are.
        if (400..<500).contains(http.statusCode) {
            throw Failure.refused(Self.reason(in: data) ?? "The support server would not take that report.")
        }
        throw Failure.notDelivered
    }

    private static func reason(in data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["error"] as? String,
            !message.isEmpty
        else { return nil }
        return message.prefix(1).uppercased() + message.dropFirst()
    }
}
