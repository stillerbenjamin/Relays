//
//  Phase6Tests.swift
//  RelaysTests
//
//  Message rules, conversation moderation, and where a report is addressed.
//

import Testing
import Foundation
@testable import Relays

@Suite("Message rules and report routing", .serialized)
struct MessageModerationTests {

    private static let session = ATSession(accessJwt: "access-1", refreshJwt: "refresh-1",
                                           handle: "tester.test", did: "did:plc:tester",
                                           email: nil, service: "https://pds.test")

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test", session: Self.session,
                      configuration: StubTransport.configuration)
    }

    // MARK: - Who may write

    @Test("An account with no declaration takes messages from anyone")
    func defaultRule() {
        #expect(MessageRule(stored: nil) == .all)
        #expect(MessageRule(stored: "") == .all)
        #expect(MessageRule(stored: "nonsense") == .all)
        #expect(MessageRule(stored: "following") == .following)
        #expect(MessageRule(stored: "none") == .none)
    }

    @Test("The rule is read from the record at its fixed key")
    func readsRule() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"uri":"at://did:plc:tester/chat.bsky.actor.declaration/self","value":{"$type":"chat.bsky.actor.declaration","allowIncoming":"following"}}"#.utf8))
        ])

        let rule = try await makeClient().messageRule()
        #expect(rule == .following)

        let request = try #require(StubTransport.requests.first)
        let query = try #require(request.url?.query)
        #expect(query.contains("rkey=self"))
        #expect(query.contains("chat.bsky.actor.declaration"))
    }

    @Test("Writing the rule replaces the one record instead of adding another")
    func writesRule() async throws {
        StubTransport.reset([.init(body: Data("{}".utf8))])
        try await makeClient().setMessageRule(.none)

        let request = try #require(StubTransport.requests.first)
        #expect(request.url?.path.hasSuffix("com.atproto.repo.putRecord") == true)

        let body = try #require(request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(contentsOf: buffer[0..<read])
            }
            return data
        })
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("\"rkey\":\"self\""))
        #expect(text.contains("\"allowIncoming\":\"none\""))
    }

    // MARK: - Conversations

    @Test("Muting and leaving reach the chat service")
    func conversationActions() async throws {
        // Each call first mints a service token, then goes to the chat host.
        StubTransport.reset([
            .init(body: Data(#"{"token":"chat-token"}"#.utf8)),
            .init(body: Data("{}".utf8)),
            .init(body: Data(#"{"token":"chat-token"}"#.utf8)),
            .init(body: Data("{}".utf8)),
        ])

        let client = makeClient()
        try await client.muteConversation(convoId: "convo-1")
        try await client.leaveConversation(convoId: "convo-1")

        let paths = StubTransport.requests.compactMap { $0.url?.path }
        #expect(paths.contains { $0.hasSuffix("chat.bsky.convo.muteConvo") })
        #expect(paths.contains { $0.hasSuffix("chat.bsky.convo.leaveConvo") })

        // The chat calls go to the chat host, not to the account's own server.
        let hosts = Set(StubTransport.requests.compactMap { $0.url?.host })
        #expect(hosts.contains("api.bsky.chat"))
        #expect(hosts.contains("pds.test"))
    }

    // MARK: - Where a report goes

    @Test("A report addressed to a service names it in the proxy header")
    func routedReport() async throws {
        StubTransport.reset([.init(body: Data("{}".utf8))])

        try await makeClient().report(subject: .account(did: "did:plc:someone"),
                                      reason: .spam, note: nil,
                                      labeler: "did:plc:strict")

        let request = try #require(StubTransport.requests.first)
        #expect(request.value(forHTTPHeaderField: "atproto-proxy")
                == "did:plc:strict#atproto_labeler")
    }

    @Test("Without a service the report carries no proxy at all")
    func unroutedReport() async throws {
        StubTransport.reset([.init(body: Data("{}".utf8))])

        try await makeClient().report(subject: .account(did: "did:plc:someone"),
                                      reason: .spam, note: nil)

        let request = try #require(StubTransport.requests.first)
        #expect(request.value(forHTTPHeaderField: "atproto-proxy") == nil)
    }

    /// A report that is retried — after a rate limit or an expired token — must
    /// still reach the service it was addressed to, not the server's default.
    @Test("A retried report keeps its address")
    func retriedReportKeepsProxy() async throws {
        StubTransport.reset([
            .init(status: 429, body: Data(#"{"error":"RateLimitExceeded"}"#.utf8),
                  headers: ["retry-after": "0"]),
            .init(body: Data("{}".utf8)),
        ])

        try await makeClient().report(subject: .account(did: "did:plc:someone"),
                                      reason: .spam, note: nil,
                                      labeler: "did:plc:strict")

        #expect(StubTransport.requests.count == 2)
        for request in StubTransport.requests {
            #expect(request.value(forHTTPHeaderField: "atproto-proxy")
                    == "did:plc:strict#atproto_labeler")
        }
    }

    // MARK: - Naming a message

    @Test("A message is reported by conversation, message and sender")
    func messageSubject() throws {
        let subject = ReportSubject.message(convoId: "convo-1", messageId: "msg-9",
                                            did: "did:plc:sender")
        let data = try JSONEncoder().encode(subject)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("chat.bsky.convo.defs#messageRef"))
        #expect(text.contains("\"convoId\":\"convo-1\""))
        #expect(text.contains("\"messageId\":\"msg-9\""))
        #expect(text.contains("\"did\":\"did:plc:sender\""))
        // A message has no URI, and must not pretend to.
        #expect(!text.contains("uri"))
    }
}
