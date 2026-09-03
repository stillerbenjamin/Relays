//
//  SessionTests.swift
//  RelaysTests
//
//  What happens when a credential stops working, and what must never happen to
//  the preferences record while it is not working.
//

import Testing
import Foundation
@testable import Relays

@Suite("A credential that stopped working", .serialized)
struct RevokedSessionTests {

    private static let session = ATSession(accessJwt: "access-1", refreshJwt: "refresh-1",
                                           handle: "tester.test", did: "did:plc:tester",
                                           email: nil, service: "https://pds.test")

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test", session: Self.session,
                      configuration: StubTransport.configuration)
    }

    private static let revoked = #"{"error":"ExpiredToken","message":"Token has been revoked"}"#

    /// The message the server sends is true but useless on its own: the screen
    /// used to show it beside a "try again" that could never work.
    @Test("A revoked token is not a retryable error")
    func revokedTokenEndsTheSession() async throws {
        StubTransport.reset([
            .init(status: 400, body: Data(Self.revoked.utf8), path: "app.bsky.actor.getProfile"),
            // Refreshing fails too — that is what revoked means.
            .init(status: 400, body: Data(Self.revoked.utf8), path: "refreshSession"),
        ])

        let client = makeClient()
        var reported: [ATSession?] = []
        await client.setSessionChangeHandler { reported.append($0) }

        await #expect(throws: ATProtoError.self) {
            _ = try await client.profile(actor: "tester.test")
        }

        // Three calls at most: the first, the refresh, and no pointless third.
        #expect(StubTransport.requests.count == 2)
        // The session was let go, and said so.
        #expect(reported.count == 1)
        #expect(reported.first ?? nil == nil)
        #expect(await client.currentSession == nil)
    }

    @Test("An expired token that can be refreshed is still just a hiccup")
    func expiredTokenRefreshes() async throws {
        let refreshed = """
        {"accessJwt":"access-2","refreshJwt":"refresh-2",
         "handle":"tester.test","did":"did:plc:tester"}
        """
        StubTransport.reset([
            .init(status: 400, body: Data(#"{"error":"ExpiredToken"}"#.utf8),
                  path: "app.bsky.actor.getProfile"),
            .init(body: Data(refreshed.utf8), path: "refreshSession"),
            .init(body: Data(#"{"did":"did:plc:tester","handle":"tester.test"}"#.utf8),
                  path: "app.bsky.actor.getProfile"),
        ])

        let client = makeClient()
        let profile = try await client.profile(actor: "tester.test")

        #expect(profile.handle == "tester.test")
        #expect(await client.currentSession?.accessJwt == "access-2")
    }

    @MainActor
    @Test("A dead session takes the app back to the login screen")
    func signsOut() async {
        StubTransport.reset([
            .init(status: 400, body: Data(Self.revoked.utf8), path: "app.bsky.actor.getProfile"),
            .init(status: 400, body: Data(Self.revoked.utf8), path: "refreshSession"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.installSessionObserverForTesting()

        await app.loadOwnProfile()

        // The handler hops to the main actor, so the sign-out lands a beat later.
        var waited = 0
        while app.session != nil, waited < 40 {
            try? await Task.sleep(for: .milliseconds(25))
            waited += 1
        }

        // Signing out from inside the handler must not call itself: `logout()`
        // reports the session going away through that very handler.
        #expect(app.session == nil)
        #expect(app.phase == .signedOut)
    }
}

@Suite("The preferences record is not overwritten blind", .serialized)
struct PreferenceSafetyTests {

    /// `putPreferences` replaces the whole array. If the read failed and the app
    /// wrote anyway, everything another client had put there — saved feeds, muted
    /// words, a birth date — would be gone.
    @MainActor
    @Test("Nothing is written while the record could not be read")
    func doesNotWriteWhatItNeverRead() async {
        StubTransport.reset([
            .init(status: 400, body: Data(#"{"error":"ExpiredToken"}"#.utf8),
                  path: "app.bsky.actor.getPreferences"),
            .init(status: 400, body: Data(#"{"error":"ExpiredToken"}"#.utf8),
                  path: "app.bsky.actor.getPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        #expect(!app.preferencesAreLoaded)
        await app.setAdultContent(true)

        let wrote = StubTransport.requests.contains {
            $0.url?.path.hasSuffix("putPreferences") == true
        }
        #expect(!wrote)
    }

    @MainActor
    @Test("Once read, a write carries everything that was in it")
    func writesTheWholeRecord() async throws {
        let stored = """
        {"preferences":[
          {"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
            {"id":"a","type":"feed","value":"at://did:plc:x/app.bsky.feed.generator/whats-hot","pinned":true}]},
          {"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"value":"spoiler","targets":["content"]}]}
        ]}
        """
        StubTransport.reset([
            .init(body: Data(stored.utf8), path: "app.bsky.actor.getPreferences"),
            .init(body: Data("{}".utf8), path: "putPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.loadModerationForTesting()
        #expect(app.preferencesAreLoaded)
        await app.setAdultContent(true)

        let request = try #require(StubTransport.requests
            .first { $0.url?.path.hasSuffix("putPreferences") == true })
        let body = try #require(Self.body(of: request))
        let text = String(decoding: body, as: UTF8.self)

        // The saved feeds have to come back out of the same call that turns a
        // moderation setting on.
        #expect(text.contains("savedFeedsPrefV2"))
        #expect(text.contains("whats-hot"))
        #expect(text.contains("mutedWordsPref"))
        #expect(text.contains("adultContentPref"))
    }

    private static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
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
    }
}
