//
//  AppPasswordTests.swift
//  RelaysTests
//
//  Relays signs in with an app password and, until now, could neither show the
//  ones on the account nor take any back — so it asked for a credential and
//  then hid it, and the only place to withdraw it was somebody else's website.
//
//  `createAppPassword` had been sitting in the client with no callers since
//  sign-up was parked. This screen gives it a use again.
//

import Testing
import Foundation
@testable import Relays

@MainActor
@Suite("App passwords", .serialized)
struct AppPasswordTests {

    private func client() async -> ATProtoClient {
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        return app.client
    }

    /// The shape the lexicon defines: names and dates, never the password. A
    /// credential that can be read back is not a credential.
    @Test("The list carries names and dates, and no passwords")
    func list() async throws {
        StubTransport.reset([
            .init(body: Data(#"""
            {"passwords":[
              {"name":"Relays","createdAt":"2026-08-29T09:23:28.000Z","privileged":true},
              {"name":"Old phone","createdAt":"2026-01-02T10:00:00.000Z"}]}
            """#.utf8), path: "com.atproto.server.listAppPasswords")
        ])

        let passwords = try await (await client()).appPasswords()
        #expect(passwords.map(\.name) == ["Relays", "Old phone"])
        #expect(passwords[0].canUseMessages)
        // An older server omits the flag, and omitted is not the same as false.
        #expect(passwords[1].privileged == nil)
        #expect(!passwords[1].canUseMessages)

        // Nothing in the reply could carry a password even if a server sent one.
        let mirror = Mirror(reflecting: passwords[0])
        #expect(!mirror.children.contains { $0.label == "password" })
    }

    @Test("Taking one back names it in the body")
    func revoke() async throws {
        StubTransport.reset([
            .init(body: Data("{}".utf8), path: "com.atproto.server.revokeAppPassword")
        ])
        try await (await client()).revokeAppPassword(name: "Old phone")

        let request = try #require(StubTransport.requests.last)
        #expect(request.url?.path.hasSuffix("com.atproto.server.revokeAppPassword") == true)
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody
                                ?? request.httpBodyStream.map { stream -> Data in
                                    stream.open(); defer { stream.close() }
                                    var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                                    while stream.hasBytesAvailable {
                                        let read = stream.read(&buffer, maxLength: buffer.count)
                                        if read <= 0 { break }
                                        data.append(contentsOf: buffer[0..<read])
                                    }
                                    return data
                                })
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "Old phone")
    }

    /// A server that does not know `privileged` rejects the call rather than
    /// ignoring the flag. A password without message access beats none.
    @Test("An older server that refuses the flag is asked again without it")
    func privilegedFallback() async throws {
        StubTransport.reset([
            .init(status: 400,
                  body: Data(#"{"error":"InvalidRequest","message":"unknown field"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
            .init(body: Data(#"{"name":"Old client","password":"abcd-efgh-ijkl-mnop","createdAt":"2026-09-04T10:00:00.000Z"}"#.utf8),
                  path: "com.atproto.server.createAppPassword")
        ])

        let password = try await (await client()).createAppPassword(name: "Old client",
                                                                    privileged: true)
        #expect(password == "abcd-efgh-ijkl-mnop")
        #expect(StubTransport.requests.filter {
            $0.url?.path.hasSuffix("createAppPassword") == true
        }.count == 2)
    }

    @Test("A date the app cannot read does not take the row down")
    func oddDate() throws {
        let json = Data(#"{"name":"x","createdAt":"whenever"}"#.utf8)
        let password = try JSONDecoder().decode(AppPassword.self, from: json)
        #expect(password.name == "x")
        // RelativeTime returns an empty string rather than throwing.
        #expect(RelativeTime.short(password.createdAt) == "")
    }
}
