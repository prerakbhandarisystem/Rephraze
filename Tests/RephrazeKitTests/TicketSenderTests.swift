import Testing
import Foundation
@testable import RephrazeKit

/// Answers with whatever the test says, and keeps what it was asked.
///
/// `@unchecked Sendable`: the transport is called once, awaited by the test
/// that made it, and never touched from anywhere else.
private final class FakeTransport: @unchecked Sendable {
    var status = 200
    var body = Data("{}".utf8)
    var throwsUp = false
    var nonHTTP = false

    private(set) var requests: [URLRequest] = []
    var lastRequest: URLRequest? { requests.last }

    var send: TicketSender.Transport {
        { [self] request in
            requests.append(request)
            if throwsUp { throw URLError(.notConnectedToInternet) }
            let response: URLResponse = nonHTTP
                ? URLResponse(url: request.url!, mimeType: nil,
                              expectedContentLength: 0, textEncodingName: nil)
                : HTTPURLResponse(url: request.url!, statusCode: status,
                                  httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }
}

@Suite("TicketSender")
struct TicketSenderTests {

    private static let endpoint = URL(string: "https://example.invalid/v1/tickets")!

    private let ticket = SupportTicket(
        kind: .bug,
        summary: "Nothing happens in Slack",
        detail: "Double-tapped and no panel appeared.",
        replyTo: "someone@example.com",
        includesDiagnostics: true,
        diagnostics: Diagnostics(fields: [.init(label: "Rephraze", value: "1.0 (1)")])
    )

    private func sender(
        _ transport: FakeTransport,
        endpoint: URL? = TicketSenderTests.endpoint
    ) -> TicketSender {
        TicketSender(endpoint: endpoint, transport: transport.send)
    }

    // MARK: - The request

    @Test("Posts the report as JSON to the endpoint")
    func postsTheReport() async throws {
        let transport = FakeTransport()
        try await sender(transport).send(ticket)

        let request = try #require(transport.lastRequest)
        #expect(request.url == Self.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let sent = try #require(request.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: sent) as? [String: Any]
        )
        #expect(body["summary"] as? String == "Nothing happens in Slack")
        #expect(body["replyTo"] as? String == "someone@example.com")
    }

    @Test("A build with no endpoint does not pretend to send")
    func noEndpoint() async {
        let transport = FakeTransport()
        let sender = sender(transport, endpoint: nil)

        #expect(!sender.canSend)
        await #expect(throws: TicketSender.Failure.nowhereToSend) {
            try await sender.send(ticket)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: - What the server says back

    @Test("Any 2xx is a report that went")
    func accepted() async throws {
        for status in [200, 201, 202] {
            let transport = FakeTransport()
            transport.status = status
            try await sender(transport).send(ticket)
        }
    }

    /// The server writes its refusals for this screen, so they are passed
    /// through rather than replaced with something vaguer.
    @Test("A refusal is shown in the server's own words")
    func refusedWithReason() async {
        let transport = FakeTransport()
        transport.status = 400
        transport.body = Data(#"{"error":"that reply address does not look like an address"}"#.utf8)

        await #expect(
            throws: TicketSender.Failure.refused(
                "That reply address does not look like an address"
            )
        ) {
            try await sender(transport).send(ticket)
        }
    }

    @Test("A refusal with nothing to say still says something")
    func refusedWithoutReason() async {
        let transport = FakeTransport()
        transport.status = 400
        transport.body = Data("not json at all".utf8)

        await #expect(throws: TicketSender.Failure.self) {
            try await sender(transport).send(ticket)
        }
    }

    @Test("A server that broke is not the sender's fault to fix")
    func serverError() async {
        let transport = FakeTransport()
        transport.status = 503

        await #expect(throws: TicketSender.Failure.notDelivered) {
            try await sender(transport).send(ticket)
        }
    }

    @Test("No network means unreachable, not refused")
    func offline() async {
        let transport = FakeTransport()
        transport.throwsUp = true

        await #expect(throws: TicketSender.Failure.unreachable) {
            try await sender(transport).send(ticket)
        }
    }

    /// Something answered, but not in HTTP -- a captive portal, a proxy. It did
    /// not arrive, and must never be reported as sent.
    @Test("An answer that is not HTTP is not a delivery")
    func nonHTTPResponse() async {
        let transport = FakeTransport()
        transport.nonHTTP = true

        await #expect(throws: TicketSender.Failure.notDelivered) {
            try await sender(transport).send(ticket)
        }
    }

    // MARK: - Wording

    @Test("Every failure has something a person can read")
    func everyFailureExplainsItself() {
        let failures: [TicketSender.Failure] = [
            .nowhereToSend, .unreachable, .refused("Nope."), .notDelivered,
        ]
        for failure in failures {
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }
}
