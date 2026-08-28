import Testing
import Foundation
@testable import RephrazeKit

@Suite("SupportTicket")
struct SupportTicketTests {

    /// Built by hand rather than read from the live app, so the tests never
    /// touch the Keychain and never depend on how this machine is configured.
    private let diagnostics = Diagnostics(fields: [
        .init(label: "Rephraze", value: "1.0 (1)"),
        .init(label: "Accessibility", value: "granted"),
    ])

    private func ticket(
        kind: TicketKind = .bug,
        summary: String = "Nothing happens in Slack",
        detail: String = "Double-tapped and no panel appeared.",
        diagnostics included: Bool = true
    ) -> SupportTicket {
        SupportTicket(
            kind: kind,
            summary: summary,
            detail: detail,
            includesDiagnostics: included,
            diagnostics: diagnostics
        )
    }

    // MARK: - Subject and body

    @Test("Subject leads with the app and the kind")
    func subjectFormat() {
        #expect(ticket().subject == "Rephraze Bug: Nothing happens in Slack")
        #expect(ticket(kind: .idea).subject.hasPrefix("Rephraze Idea:"))
        #expect(ticket(kind: .question).subject.hasPrefix("Rephraze Question:"))
    }

    @Test("Subject and body are trimmed")
    func trimsWhitespace() {
        let padded = ticket(summary: "  spaced  ", detail: "\n  body  \n")
        #expect(padded.subject == "Rephraze Bug: spaced")
        #expect(padded.body.hasPrefix("body"))
    }

    @Test("Diagnostics ride along under a divider")
    func bodyWithDiagnostics() {
        let body = ticket().body
        #expect(body.hasPrefix("Double-tapped and no panel appeared."))
        #expect(body.contains("---"))
        #expect(body.contains("Rephraze: 1.0 (1)"))
        #expect(body.contains("Accessibility: granted"))
    }

    @Test("Switching diagnostics off leaves nothing but what was written")
    func bodyWithoutDiagnostics() {
        let body = ticket(diagnostics: false).body
        #expect(body == "Double-tapped and no panel appeared.")
        #expect(!body.contains("Accessibility"))
    }

    // MARK: - Sendability

    @Test("A summary is the whole requirement")
    func sendability() {
        #expect(ticket().isSendable)
        #expect(ticket(detail: "").isSendable)
        #expect(!ticket(summary: "").isSendable)
        #expect(!ticket(summary: "   \n ").isSendable)
    }

    // MARK: - mailto

    @Test("Builds a mailto for the given address")
    func mailtoBasics() throws {
        let url = try #require(ticket().mailtoURL(to: "help@example.com"))
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:help@example.com?"))
        #expect(url.absoluteString.contains("subject="))
        #expect(url.absoluteString.contains("&body="))
    }

    /// The one that matters: an unescaped `&` in what someone types would end
    /// the body parameter early and silently drop the rest of their report.
    @Test("Query delimiters in the text are escaped, not left to split the URL")
    func escapesDelimiters() throws {
        let url = try #require(
            ticket(summary: "A & B", detail: "x=1&y=2 ? # + done")
                .mailtoURL(to: "help@example.com")
        )
        let text = url.absoluteString

        #expect(text.contains("%26"))          // &
        #expect(text.contains("%3D"))          // =
        #expect(text.contains("%3F"))          // ?
        #expect(text.contains("%23"))          // #
        #expect(text.contains("%2B"))          // +

        // Exactly two parameters: the ampersand between them, and no others.
        #expect(text.components(separatedBy: "&").count == 2)
    }

    @Test("Line breaks survive as escapes")
    func escapesNewlines() throws {
        let url = try #require(
            ticket(detail: "one\ntwo").mailtoURL(to: "help@example.com")
        )
        #expect(url.absoluteString.contains("%0A"))
    }

    @Test("Round-trips back to the text that went in")
    func decodesBack() throws {
        let sent = ticket(summary: "A & B", detail: "x=1&y=2")
        let url = try #require(sent.mailtoURL(to: "help@example.com"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        let subject = try #require(components.queryItems?.first { $0.name == "subject" }?.value)

        #expect(subject == sent.subject)
        #expect(body == sent.body)
    }

    // MARK: - Length

    @Test("An over-long report is cut with a note rather than silently")
    func truncatesLongDetail() {
        let long = String(repeating: "a", count: SupportTicket.maxBodyLength * 2)
        let body = ticket(detail: long).body

        #expect(body.count <= SupportTicket.maxBodyLength)
        #expect(body.contains("cut here"))
        // The diagnostics are short and the most useful part, so they stay.
        #expect(body.contains("Accessibility: granted"))
    }

    @Test("A report that fits is left alone")
    func keepsShortDetail() {
        #expect(!ticket().body.contains("cut here"))
    }

    // MARK: - Clipboard fallback

    @Test("Plain text carries the address, the subject and the body")
    func plainText() {
        let text = ticket().plainText(to: "help@example.com")
        #expect(text.contains("To: help@example.com"))
        #expect(text.contains("Subject: Rephraze Bug: Nothing happens in Slack"))
        #expect(text.contains("Double-tapped and no panel appeared."))
    }

    // MARK: - Diagnostics

    @Test("Diagnostics render as one label-and-value line each")
    func diagnosticsText() {
        #expect(diagnostics.text == "Rephraze: 1.0 (1)\nAccessibility: granted")
    }
}
