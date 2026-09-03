//
//  SignUpTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

// MARK: - What a server asks for

@Suite("Sign-up form")
struct SignUpFormTests {

    private func description(invite: Bool = false, phone: Bool = false,
                             suffix: String = ".bsky.social") -> ServerDescription {
        ServerDescription(did: "did:web:pds.test",
                          inviteCodeRequired: invite,
                          phoneVerificationRequired: phone,
                          availableUserDomains: [suffix],
                          links: .init(privacyPolicy: "https://pds.test/privacy",
                                       termsOfService: "https://pds.test/terms"))
    }

    @Test("The server's own suffix completes the handle")
    func handleSuffix() {
        var draft = SignUpDraft()
        draft.handle = "maria"
        #expect(draft.fullHandle(on: description()) == "maria.bsky.social")

        // Somebody bringing their own domain keeps it.
        draft.handle = "maria.example.com"
        #expect(draft.fullHandle(on: description()) == "maria.example.com")

        // A leading @ and stray case are the two things people actually type.
        draft.handle = "@Maria"
        #expect(draft.fullHandle(on: description()) == "maria.bsky.social")

        // A server that names no domain gets the handle as typed.
        draft.handle = "maria"
        #expect(draft.fullHandle(on: description(suffix: "")) == "maria")
    }

    @Test("A form is only complete once the server's own conditions are met")
    func completeness() {
        var draft = SignUpDraft()
        draft.handle = "maria"
        draft.email = "maria@example.com"
        draft.password = "at-least-8"
        draft.acceptedTerms = true

        let plain = description()
        #expect(draft.isComplete(for: plain))

        // An invite server refuses the same form until the code is there.
        let invited = description(invite: true)
        #expect(!draft.isComplete(for: invited))
        draft.inviteCode = "pds-test-abcde"
        #expect(draft.isComplete(for: invited))

        // A phone server wants the code from the message, not just the number.
        let texted = description(phone: true)
        draft.phone = "+491700000000"
        #expect(!draft.isComplete(for: texted))
        draft.phoneCode = "123456"
        #expect(draft.isComplete(for: texted))
    }

    @Test("Nothing is sent to a server that never answered")
    func unreachableServer() {
        var draft = SignUpDraft()
        draft.handle = "maria"
        draft.email = "maria@example.com"
        draft.password = "at-least-8"
        draft.acceptedTerms = true

        // Everything filled in, but the server never described itself: the form
        // has no idea whether an invite or a phone number is missing.
        #expect(!draft.isComplete(for: nil))
        #expect(draft.isComplete(for: description()))
    }

    @Test("The things a server refuses are caught before it is asked")
    func localRefusals() {
        var draft = SignUpDraft()
        draft.handle = "maria"
        draft.email = "maria@example.com"
        draft.password = "at-least-8"
        draft.acceptedTerms = true

        draft.password = "short"
        #expect(!draft.passwordIsLongEnough)
        #expect(!draft.isComplete(for: description()))
        draft.password = "at-least-8"

        draft.email = "not-an-address"
        #expect(!draft.emailLooksLikeOne)
        #expect(!draft.isComplete(for: description()))
        draft.email = "maria@example.com"

        // Thirteen is the network's own floor.
        draft.birthDate = Calendar.current.date(byAdding: .year, value: -9, to: Date())!
        #expect(!draft.isOldEnough)
        #expect(!draft.isComplete(for: description()))

        draft.birthDate = Calendar.current.date(byAdding: .year, value: -13, to: Date())!
        #expect(draft.isOldEnough)

        // Terms are not a formality; nothing is sent without them.
        draft.acceptedTerms = false
        #expect(!draft.isComplete(for: description()))
    }

    @Test("A description decodes as the real ones arrive")
    func decodesDescription() throws {
        // Byte for byte what bsky.social answered.
        let payload = """
        {"did":"did:web:bsky.social","availableUserDomains":[".bsky.social"],
         "inviteCodeRequired":false,"phoneVerificationRequired":true,
         "links":{"privacyPolicy":"https://bsky.social/about/support/privacy-policy",
                  "termsOfService":"https://bsky.social/about/support/tos"}}
        """
        let described = try JSONDecoder().decode(ServerDescription.self, from: Data(payload.utf8))

        #expect(described.needsPhone)
        #expect(!described.needsInviteCode)
        #expect(described.handleSuffix == ".bsky.social")
        #expect(described.termsURL != nil)
        #expect(described.privacyPolicyURL != nil)

        // A server that leaves fields out must still describe itself. A default
        // value in the struct is not enough — the decoder demands the key.
        let sparse = try JSONDecoder().decode(
            ServerDescription.self, from: Data(#"{"did":"did:web:pds.test"}"#.utf8))
        #expect(!sparse.needsPhone)
        #expect(!sparse.needsInviteCode)
        #expect(sparse.handleSuffix.isEmpty)
    }
}

// MARK: - Against the model

@Suite("Sign-up", .serialized)
struct SignUpTests {

    private var draft: SignUpDraft {
        var draft = SignUpDraft()
        draft.host = "pds.test"
        draft.handle = "maria"
        draft.email = "maria@example.com"
        draft.password = "the-real-password"
        draft.acceptedTerms = true
        return draft
    }

    private var description: ServerDescription {
        ServerDescription(did: "did:web:pds.test", inviteCodeRequired: false,
                          phoneVerificationRequired: false,
                          availableUserDomains: [".pds.test"], links: nil)
    }

    private static let created = """
    {"accessJwt":"full-access","refreshJwt":"full-refresh",
     "handle":"maria.pds.test","did":"did:plc:maria"}
    """
    private static let exchanged = """
    {"accessJwt":"app-access","refreshJwt":"app-refresh",
     "handle":"maria.pds.test","did":"did:plc:maria"}
    """

    /// The account password may reach `createAccount` and nothing else. What is
    /// kept afterwards has to be the session that came from the app password.
    @MainActor
    @Test("The real password is spent once and never stored")
    func exchangesForAnAppPassword() async throws {
        StubTransport.reset([
            .init(body: Data(Self.created.utf8), path: "com.atproto.server.createAccount"),
            .init(body: Data(#"{"password":"abcd-efgh-ijkl-mnop"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
            .init(body: Data(Self.exchanged.utf8), path: "com.atproto.server.createSession"),
            .init(body: Data(#"{"preferences":[]}"#.utf8), path: "getPreferences"),
            .init(body: Data("{}".utf8), path: "putPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        try await app.signUp(draft: draft, description: description)

        #expect(app.session?.accessJwt == "app-access")
        #expect(app.phase == .signedIn)

        // The account password appears in exactly one request body: the one that
        // made the account.
        let bodies = StubTransport.requests.map { request -> String in
            guard let data = Self.body(of: request) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
        let carrying = bodies.filter { $0.contains("the-real-password") }
        #expect(carrying.count == 1)
        #expect(carrying.first?.contains("com.atproto.server.createAccount") != true)

        // The session that was created first is not the one that survived.
        #expect(!bodies.contains { $0.contains("full-refresh") })
    }

    @MainActor
    @Test("A server that rejects the privileged flag still yields an account")
    func fallsBackToAPlainAppPassword() async throws {
        StubTransport.reset([
            .init(body: Data(Self.created.utf8), path: "com.atproto.server.createAccount"),
            // First call refused, second accepted — the client tries again without
            // the flag rather than giving up on the whole sign-up.
            .init(status: 400, body: Data(#"{"error":"InvalidRequest","message":"unknown field"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
            .init(body: Data(#"{"password":"abcd-efgh-ijkl-mnop"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
            .init(body: Data(Self.exchanged.utf8), path: "com.atproto.server.createSession"),
            .init(body: Data(#"{"preferences":[]}"#.utf8), path: "getPreferences"),
            .init(body: Data("{}".utf8), path: "putPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        try await app.signUp(draft: draft, description: description)

        #expect(app.session?.accessJwt == "app-access")
        #expect(app.phase == .signedIn)
    }

    /// The account exists the moment `createAccount` returns. Nothing after that
    /// may leave the user outside.
    @MainActor
    @Test("An account survives a failure that comes after it")
    func survivesLaterFailures() async throws {
        StubTransport.reset([
            .init(body: Data(Self.created.utf8), path: "com.atproto.server.createAccount"),
            .init(status: 500, body: Data(#"{"error":"InternalServerError"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
            .init(status: 500, body: Data(#"{"error":"InternalServerError"}"#.utf8),
                  path: "com.atproto.server.createAppPassword"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        try await app.signUp(draft: draft, description: description)

        // Signed in on the session the account came with, rather than thrown out.
        #expect(app.phase == .signedIn)
        #expect(app.session?.accessJwt == "full-access")
    }

    @MainActor
    @Test("The birth date is written without wiping what is already there")
    func keepsExistingPreferences() async throws {
        StubTransport.reset([
            .init(body: Data(Self.created.utf8), path: "com.atproto.server.createAccount"),
            .init(body: Data(#"{"password":"abcd"}"#.utf8), path: "createAppPassword"),
            .init(body: Data(Self.exchanged.utf8), path: "createSession"),
            .init(body: Data(#"{"preferences":[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[]}]}"#.utf8),
                  path: "getPreferences"),
            .init(body: Data("{}".utf8), path: "putPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        try await app.signUp(draft: draft, description: description)

        let request = try #require(StubTransport.requests
            .first { $0.url?.path.hasSuffix("putPreferences") == true })
        let written = try #require(Self.body(of: request))
        let text = String(decoding: written, as: UTF8.self)

        #expect(text.contains("personalDetailsPref"))
        #expect(text.contains("birthDate"))
        #expect(text.contains("savedFeedsPrefV2"))
    }

    // MARK: - Leaving

    @MainActor
    @Test("Deleting takes the code, the password and the account's own DID")
    func deletes() async throws {
        StubTransport.reset([
            .init(body: Data("{}".utf8), path: "requestAccountDelete"),
            .init(body: Data("{}".utf8), path: "deleteAccount"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        try await app.requestAccountDeletion()
        try await app.deleteAccount(password: "the-real-password", token: "123456")

        let request = try #require(StubTransport.requests
            .first { $0.url?.path.hasSuffix("deleteAccount") == true })
        let body = try #require(Self.body(of: request))
        let text = String(decoding: body, as: UTF8.self)

        #expect(text.contains("did:plc:tester"))
        #expect(text.contains("123456"))
        #expect(text.contains("the-real-password"))
        #expect(app.session == nil)
    }

    // MARK: - Reading a request body back

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

// MARK: - Discovering

@Suite("Keeping a feed", .serialized)
struct SavedFeedTests {

    /// Keeping a feed writes the same record that carries muted words, labeler
    /// subscriptions and the birth date. It has to leave all of them alone.
    @MainActor
    @Test("Subscribing carries the rest of the record along")
    func keepsEverythingElse() async throws {
        let stored = """
        {"preferences":[
          {"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
            {"id":"one","type":"timeline","value":"following","pinned":true}]},
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

        #expect(app.savedFeeds.count == 1)
        #expect(!app.isSaved("at://did:plc:x/app.bsky.feed.generator/whats-hot"))

        await app.toggleSavedFeed("at://did:plc:x/app.bsky.feed.generator/whats-hot")

        let request = try #require(StubTransport.requests
            .first { $0.url?.path.hasSuffix("putPreferences") == true })
        let text = String(decoding: try #require(Self.body(of: request)), as: UTF8.self)

        #expect(text.contains("whats-hot"))
        #expect(text.contains("following"), "the timeline entry was dropped")
        #expect(text.contains("mutedWordsPref"), "the muted words were dropped")
        #expect(app.isSaved("at://did:plc:x/app.bsky.feed.generator/whats-hot"))
    }

    @MainActor
    @Test("Removing takes only the one feed away")
    func removesOne() async throws {
        let stored = """
        {"preferences":[{"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
          {"id":"one","type":"timeline","value":"following","pinned":true},
          {"id":"two","type":"feed","value":"at://x/app.bsky.feed.generator/hot","pinned":true}]}]}
        """
        StubTransport.reset([
            .init(body: Data(stored.utf8), path: "app.bsky.actor.getPreferences"),
            .init(body: Data("{}".utf8), path: "putPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.loadModerationForTesting()
        #expect(app.savedFeeds.count == 2)

        await app.toggleSavedFeed("at://x/app.bsky.feed.generator/hot")

        #expect(app.savedFeeds.count == 1)
        #expect(app.savedFeeds.first?.value == "following")
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
