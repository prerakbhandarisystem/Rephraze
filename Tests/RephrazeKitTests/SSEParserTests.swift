import Testing
import Foundation
@testable import RephrazeKit

@Suite("SSEParser")
struct SSEParserTests {

    private func d(_ s: String) -> Data { Data(s.utf8) }

    @Test("A whole event in one chunk")
    func singleChunk() {
        var parser = SSEParser()
        let events = parser.consume(d("data: {\"a\":1}\n"))
        #expect(events == [.data("{\"a\":1}")])
    }

    @Test("[DONE] ends the stream")
    func doneEvent() {
        var parser = SSEParser()
        #expect(parser.consume(d("data: [DONE]\n")) == [.done])
    }

    /// The real reason this class exists: the network does not respect line
    /// boundaries, so one line can arrive across several chunks.
    @Test("A line split across three chunks")
    func splitAcrossChunks() {
        var parser = SSEParser()
        #expect(parser.consume(d("data: {\"he")).isEmpty)
        #expect(parser.consume(d("llo\":")).isEmpty)
        #expect(parser.consume(d("1}\n")) == [.data("{\"hello\":1}")])
    }

    @Test("Several events in one chunk")
    func multipleEventsOneChunk() {
        var parser = SSEParser()
        let events = parser.consume(d("data: one\ndata: two\ndata: [DONE]\n"))
        #expect(events == [.data("one"), .data("two"), .done])
    }

    @Test("Blank lines between events are ignored")
    func blankLinesIgnored() {
        var parser = SSEParser()
        #expect(parser.consume(d("data: one\n\n\ndata: two\n")) == [.data("one"), .data("two")])
    }

    @Test("Comment lines are ignored")
    func commentsIgnored() {
        var parser = SSEParser()
        #expect(parser.consume(d(": keep-alive\ndata: one\n")) == [.data("one")])
    }

    @Test("Non-data lines are ignored")
    func nonDataLinesIgnored() {
        var parser = SSEParser()
        #expect(parser.consume(d("event: message\nid: 5\ndata: one\n")) == [.data("one")])
    }

    @Test("A final line with no trailing newline is flushed")
    func finishFlushesRemainder() {
        var parser = SSEParser()
        #expect(parser.consume(d("data: last")).isEmpty)
        #expect(parser.finish() == [.data("last")])
    }

    @Test("finish() on an empty buffer yields nothing")
    func finishEmpty() {
        var parser = SSEParser()
        #expect(parser.finish().isEmpty)
    }

    /// A chunk can split a multi-byte character in half.
    @Test("Multi-byte characters split mid-character survive")
    func splitMultibyteCharacter() {
        var parser = SSEParser()
        let full = Array(d("data: caf\u{00E9}\n"))
        let cut = full.count - 3   // lands inside the é
        #expect(parser.consume(Data(full[0..<cut])).isEmpty)
        #expect(parser.consume(Data(full[cut...])) == [.data("café")])
    }
}

@Suite("OpenAI delta extraction")
struct DeltaExtractionTests {

    @Test("Pulls content out of a normal chunk")
    func extractsContent() {
        let json = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
        #expect(OpenAIClient.extractDelta(json) == "Hello")
    }

    @Test("Role-only opening chunk yields nothing")
    func roleChunkYieldsNil() {
        let json = #"{"choices":[{"delta":{"role":"assistant"}}]}"#
        #expect(OpenAIClient.extractDelta(json) == nil)
    }

    @Test("Final chunk with finish_reason yields nothing")
    func finishChunkYieldsNil() {
        let json = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        #expect(OpenAIClient.extractDelta(json) == nil)
    }

    @Test("Malformed JSON yields nothing rather than throwing")
    func malformedYieldsNil() {
        #expect(OpenAIClient.extractDelta("not json") == nil)
        #expect(OpenAIClient.extractDelta("") == nil)
    }

    @Test("Whitespace-only content is preserved")
    func whitespaceContentPreserved() {
        let json = #"{"choices":[{"delta":{"content":" "}}]}"#
        #expect(OpenAIClient.extractDelta(json) == " ")
    }
}
