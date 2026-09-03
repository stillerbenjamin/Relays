//
//  ClientTests.swift
//  RelaysTests
//
//  The client against a stubbed transport. This is the layer where a mistake
//  loses data quietly, and until now it was the least examined one.
//

import Testing
import Foundation
@testable import Relays

/// Answers requests from a queue of canned responses and records what was asked.
final class StubTransport: URLProtocol, @unchecked Sendable {

    struct Reply {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
        var headers: [String: String] = [:]
        var error: Error?
        /// Matched against the request path when set. Requests that go out at the
        /// same time arrive in no particular order, so a queue alone cannot say
        /// which answer belongs to which call.
        var path: String?
    }

    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ queued: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        replies = queued
        recorded = []
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubTransport.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let path = request.url?.path ?? ""
        let match = Self.replies.firstIndex { named in
            guard let wanted = named.path else { return false }
            return path.hasSuffix(wanted)
        }
        let index = match ?? Self.replies.firstIndex { $0.path == nil }
        let reply = index.map { Self.replies.remove(at: $0) } ?? Reply()
        Self.lock.unlock()

        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Client transport", .serialized)
struct ClientTransportTests {

    private func json(_ value: String) -> Data { Data(value.utf8) }

    private func makeClient(session: ATSession? = sampleSession) -> ATProtoClient {
        ATProtoClient(service: "https://pds.test", session: session,
                      configuration: StubTransport.configuration)
    }

    private static let sampleSession = ATSession(
        accessJwt: "access-1", refreshJwt: "refresh-1",
        handle: "tester.test", did: "did:plc:tester", email: nil,
        service: "https://pds.test")

    @Test("A successful call decodes and carries the bearer token")
    func happyPath() async throws {
        StubTransport.reset([.init(body: json(#"{"feed":[],"cursor":null}"#))])

        let client = makeClient()
        let response = try await client.timeline()

        #expect(response.feed.isEmpty)
        let request = try #require(StubTransport.requests.first)
        #expect(request.url?.path == "/xrpc/app.bsky.feed.getTimeline")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    }

    /// The case that keeps a session alive across days: the server rejects the
    /// access token, the client renews it and replays the original call.
    @Test("An expired token is refreshed and the call replayed")
    func refreshesExpiredToken() async throws {
        StubTransport.reset([
            .init(status: 400, body: json(#"{"error":"ExpiredToken","message":"Token has expired"}"#)),
            .init(body: json(#"{"accessJwt":"access-2","refreshJwt":"refresh-2","handle":"tester.test","did":"did:plc:tester"}"#)),
            .init(body: json(#"{"feed":[],"cursor":null}"#))
        ])

        let client = makeClient()
        _ = try await client.timeline()

        let requests = StubTransport.requests
        #expect(requests.count == 3)
        #expect(requests[1].url?.path == "/xrpc/com.atproto.server.refreshSession")
        // The replay must carry the new token, not the stale one.
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test("Without a refresh token an expired session surfaces as an error")
    func refreshFailure() async throws {
        StubTransport.reset([
            .init(status: 400, body: json(#"{"error":"ExpiredToken"}"#)),
            .init(status: 400, body: json(#"{"error":"ExpiredToken"}"#))
        ])

        let session = ATSession(accessJwt: "access-1", refreshJwt: "", handle: "t.test",
                                did: "did:plc:t", email: nil, service: "https://pds.test")
        let client = makeClient(session: session)

        await #expect(throws: (any Error).self) {
            _ = try await client.timeline()
        }
    }

    @Test("A rate limit is waited out once, then the call goes through")
    func rateLimited() async throws {
        StubTransport.reset([
            .init(status: 429, headers: ["retry-after": "0"]),
            .init(body: json(#"{"feed":[],"cursor":null}"#))
        ])

        let client = makeClient()
        _ = try await client.timeline()
        #expect(StubTransport.requests.count == 2)
    }

    @Test("Retry-after is read from either header form")
    func retryDelay() throws {
        let url = URL(string: "https://pds.test")!
        let seconds = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                      headerFields: ["retry-after": "12"])!
        #expect(ATProtoClient.retryDelay(from: seconds) == 12)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                    headerFields: ["ratelimit-reset": "1000009"])!
        #expect(ATProtoClient.retryDelay(from: reset, now: now) == 9)

        let none = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: [:])!
        #expect(ATProtoClient.retryDelay(from: none) == 0)
    }

    @Test("Malformed JSON becomes a decoding error, not a crash")
    func brokenBody() async throws {
        StubTransport.reset([.init(body: json("{ this is not json"))])
        let client = makeClient()

        await #expect(throws: (any Error).self) {
            _ = try await client.timeline()
        }
    }

    @Test("A server error keeps the message the server sent")
    func serverError() async throws {
        StubTransport.reset([
            .init(status: 400, body: json(#"{"error":"InvalidRequest","message":"actor is required"}"#))
        ])
        let client = makeClient()

        do {
            _ = try await client.profile(actor: "")
            Issue.record("expected the call to throw")
        } catch let error as ATProtoError {
            #expect(error.errorDescription == "actor is required")
        }
    }

    @Test("Being offline and a server not answering are told apart")
    func offline() async throws {
        // A request that never left the device and a server that will not answer
        // are two different problems, and the app used to say the same about both.
        StubTransport.reset([.init(error: URLError(.notConnectedToInternet))])
        do {
            _ = try await makeClient().timeline()
            Issue.record("expected the call to throw")
        } catch let error as ATProtoError {
            guard case .offline = error else {
                Issue.record("expected an offline error, got \(error)")
                return
            }
        }

        StubTransport.reset([.init(error: URLError(.cannotFindHost))])
        do {
            _ = try await makeClient().timeline()
            Issue.record("expected the call to throw")
        } catch let error as ATProtoError {
            guard case .transport = error else {
                Issue.record("expected a transport error, got \(error)")
                return
            }
        }
    }

    @Test("Posting sends the record the lexicon describes")
    func createPost() async throws {
        StubTransport.reset([
            .init(body: json(#"{"uri":"at://did:plc:tester/app.bsky.feed.post/1","cid":"bafy"}"#))
        ])

        let client = makeClient()
        _ = try await client.createPost(text: "Hallo #atproto")

        let request = try #require(StubTransport.requests.first)
        #expect(request.url?.path == "/xrpc/com.atproto.repo.createRecord")

        // URLProtocol strips httpBody into a stream, so read it back from there.
        let body = try #require(request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        })
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("app.bsky.feed.post"))
        #expect(text.contains("\"repo\":\"did:plc:tester\""))
        #expect(text.contains("richtext.facet#tag") || text.contains("facets"))
    }

    @Test("Uploading a blob sends the bytes with their type")
    func uploadBlob() async throws {
        StubTransport.reset([
            .init(body: json(#"{"blob":{"$type":"blob","ref":{"$link":"bafkrei"},"mimeType":"image/jpeg","size":9}}"#))
        ])

        let client = makeClient()
        let blob = try await client.uploadBlob(data: Data(repeating: 7, count: 9), mimeType: "image/jpeg")

        #expect(blob.ref.link == "bafkrei")
        let request = try #require(StubTransport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
    }
}

extension ClientTransportTests {

    /// A limit that asks for longer than the app is willing to block reaches the
    /// caller as an error instead of freezing the interface.
    @Test("A long rate limit is not waited out")
    func longRateLimit() async throws {
        StubTransport.reset([
            .init(status: 429, headers: ["retry-after": "600"])
        ])
        let client = ATProtoClient(service: "https://pds.test",
                                   session: ATSession(accessJwt: "a", refreshJwt: "r",
                                                      handle: "t.test", did: "did:plc:t",
                                                      email: nil, service: "https://pds.test"),
                                   configuration: StubTransport.configuration)

        await #expect(throws: (any Error).self) {
            _ = try await client.timeline()
        }
        #expect(StubTransport.requests.count == 1)
    }
}

@Suite("Feed paging", .serialized)
@MainActor
struct FeedPagingTests {

    private func post(_ handle: String, _ text: String) -> FeedViewPost {
        let author = ActorProfile(did: "did:plc:\(handle)", handle: handle, displayName: nil,
                                  avatar: nil, banner: nil, description: nil,
                                  followersCount: nil, followsCount: nil, postsCount: nil, viewer: nil)
        let view = PostView(uri: "at://did:plc:\(handle)/app.bsky.feed.post/\(text.hashValue)",
                            cid: "bafy", author: author, record: PostRecord(text: text),
                            embed: nil, replyCount: 0, repostCount: 0, likeCount: 0,
                            indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
        return FeedViewPost(post: view)
    }

    /// The reported behaviour: with a strict rule, a page could arrive containing
    /// nothing the reader may see, and the list simply stopped.
    @Test("Paging keeps going when a whole page is filtered away")
    func pagesPastFilteredPages() async throws {
        let hidden = #"{"feed":[{"post":{"uri":"at://did:plc:x/app.bsky.feed.post/1","cid":"c","author":{"did":"did:plc:x","handle":"spam.test"},"record":{"text":"buy now"},"indexedAt":"2026-08-29T00:00:00Z"}}],"cursor":"2"}"#
        let visible = #"{"feed":[{"post":{"uri":"at://did:plc:y/app.bsky.feed.post/2","cid":"c","author":{"did":"did:plc:y","handle":"ok.test"},"record":{"text":"hallo"},"indexedAt":"2026-08-29T00:00:00Z"}}],"cursor":"3"}"#

        StubTransport.reset([
            .init(body: Data(#"{"feed":[],"cursor":"1"}"#.utf8)),   // initial load
            .init(body: Data(hidden.utf8)),                          // filtered away
            .init(body: Data(visible.utf8))                          // survives
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        app.rules.add(FeedRule(kind: .keyword, value: "buy now"))
        defer { app.rules.rules.forEach(app.rules.remove) }

        let model = FeedModel(source: .timeline)
        await model.reload(app: app)
        await model.loadMore(app: app)

        // Three calls: one initial, then two pages until something got through.
        #expect(StubTransport.requests.count == 3)
        #expect(model.posts.count == 2)
    }
}

@Suite("Video upload", .serialized)
struct VideoUploadTests {

    private static let session = ATSession(accessJwt: "access-1", refreshJwt: "refresh-1",
                                           handle: "tester.test", did: "did:plc:tester",
                                           email: nil, service: "https://pds.test")

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test", session: Self.session,
                      configuration: StubTransport.configuration)
    }

    /// The upload goes to a different host than every other call, with a token the
    /// PDS mints for that audience — easy to get wrong, invisible when it is.
    @Test("The upload is addressed to the video service with its own token")
    func addressing() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"token":"service-token"}"#.utf8)),
            .init(body: Data(#"{"jobStatus":{"jobId":"job-1","state":"JOB_STATE_CREATED"}}"#.utf8))
        ])

        let client = makeClient()
        let job = try await client.uploadVideo(data: Data(repeating: 1, count: 32), filename: "clip.mp4")
        #expect(job.jobId == "job-1")

        let requests = StubTransport.requests
        #expect(requests[0].url?.path == "/xrpc/com.atproto.server.getServiceAuth")
        // Colons are legal in a query value and are not escaped.
        #expect(requests[0].url?.query?.contains("aud=did:web:video.bsky.app") == true)
        #expect(requests[0].url?.query?.contains("lxm=app.bsky.video.uploadVideo") == true)

        let upload = requests[1]
        #expect(upload.url?.host == "video.bsky.app")
        #expect(upload.value(forHTTPHeaderField: "Authorization") == "Bearer service-token")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
        #expect(upload.url?.query?.contains("name=clip.mp4") == true)
    }

    @Test("Waiting returns the blob once processing finishes")
    func waitsForCompletion() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"jobStatus":{"jobId":"job-1","state":"JOB_STATE_RUNNING","progress":40}}"#.utf8)),
            .init(body: Data(#"{"jobStatus":{"jobId":"job-1","state":"JOB_STATE_COMPLETED","blob":{"$type":"blob","ref":{"$link":"bafvideo"},"mimeType":"video/mp4","size":32}}}"#.utf8))
        ])

        let client = makeClient()
        let running = VideoJob(jobId: "job-1", state: "JOB_STATE_RUNNING", progress: 10)

        var seen: [Int] = []
        let blob = try await client.awaitVideo(job: running) { seen.append($0) }

        #expect(blob.ref.link == "bafvideo")
        #expect(seen.first == 10)
    }

    @Test("A failed job throws instead of waiting forever")
    func failedJob() async throws {
        StubTransport.reset([])
        let client = makeClient()
        let failed = VideoJob(jobId: "job-1", state: "JOB_STATE_FAILED",
                              progress: nil, blob: nil,
                              error: "unsupported_format", message: "Format not supported")

        await #expect(throws: (any Error).self) {
            _ = try await client.awaitVideo(job: failed) { _ in }
        }
    }

    @Test("A video embed encodes under its own type")
    func embedEncoding() throws {
        let blob = BlobRef(ref: .init(link: "bafvideo"), mimeType: "video/mp4", size: 32)
        let payload = ATProtoClient.PostEmbedPayload.make(
            images: nil,
            video: ATProtoClient.VideoEmbed(video: blob, alt: "Clip",
                                            aspectRatio: .init(width: 1280, height: 720)),
            quoting: StrongRef(uri: "at://x", cid: "c"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try #require(String(data: try encoder.encode(payload), encoding: .utf8))

        // A video wins over a quote: the record cannot carry both.
        #expect(json.contains("\"$type\":\"app.bsky.embed.video\""))
        #expect(!json.contains("app.bsky.embed.record"))
        #expect(json.contains("bafvideo"))
    }

    @Test("Quote and pictures together use the combined embed")
    func quoteWithMedia() throws {
        let blob = BlobRef(ref: .init(link: "bafimage"), mimeType: "image/jpeg", size: 12)
        let images = ATProtoClient.ImagesEmbed(images: [.init(image: blob, alt: "", aspectRatio: nil)])
        let payload = ATProtoClient.PostEmbedPayload.make(
            images: images, quoting: StrongRef(uri: "at://quoted", cid: "c"))

        let json = try #require(String(data: try JSONEncoder().encode(payload), encoding: .utf8))
        #expect(json.contains("app.bsky.embed.recordWithMedia"))
        #expect(json.contains("app.bsky.embed.images"))
        #expect(json.contains("at:\\/\\/quoted") || json.contains("at://quoted"))
    }
}

@Suite("Server discovery", .serialized)
struct ServiceDiscoveryTests {

    private var stubSession: URLSession {
        URLSession(configuration: StubTransport.configuration)
    }

    private func document(_ endpoint: String) -> Data {
        let json = """
        {"service":[{"id":"#atproto_pds","type":"AtprotoPersonalDataServer",\
        "serviceEndpoint":"\(endpoint)"}]}
        """
        return Data(json.utf8)
    }

    /// Nobody should have to know where their account lives. Two public lookups
    /// answer it: handle to DID, DID to server.
    @Test("A handle resolves to the server that hosts it")
    func resolvesHandle() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"did":"did:plc:abc"}"#.utf8)),
            .init(body: document("https://pds.example.com"))
        ])

        let service = await PDSDirectory.resolveService(for: "anna.example.com", session: stubSession)
        #expect(service == "https://pds.example.com")

        let requests = StubTransport.requests
        #expect(requests[0].url?.path == "/xrpc/com.atproto.identity.resolveHandle")
        #expect(requests[1].url?.absoluteString == "https://plc.directory/did:plc:abc")
    }

    @Test("A DID skips the handle lookup")
    func resolvesDID() async throws {
        StubTransport.reset([.init(body: document("https://own.example.org"))])

        let service = await PDSDirectory.resolveService(for: "did:plc:xyz", session: stubSession)
        #expect(service == "https://own.example.org")
        #expect(StubTransport.requests.count == 1)
    }

    @Test("A leading @ is not part of the handle")
    func stripsAt() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"did":"did:plc:abc"}"#.utf8)),
            .init(body: document("https://pds.example.com"))
        ])

        _ = await PDSDirectory.resolveService(for: "@anna.example.com", session: stubSession)
        let query = try #require(StubTransport.requests.first?.url?.query)
        #expect(query.contains("handle=anna.example.com"))
    }

    /// Anything unresolvable returns nil so the caller falls back to the default,
    /// rather than blocking a sign-in that would have worked.
    @Test("Unresolvable input yields nothing instead of an error")
    func unresolvable() async throws {
        StubTransport.reset([.init(status: 400, body: Data(#"{"error":"InvalidRequest"}"#.utf8))])
        #expect(await PDSDirectory.resolveService(for: "alice", session: stubSession) == nil)

        StubTransport.reset([])
        #expect(await PDSDirectory.resolveService(for: "", session: stubSession) == nil)
    }
}

@Suite("Chat access", .serialized)
struct ChatAccessTests {

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test",
                      session: ATSession(accessJwt: "a", refreshJwt: "r", handle: "t.test",
                                         did: "did:plc:t", email: nil, service: "https://pds.test"),
                      configuration: StubTransport.configuration)
    }

    /// The rejection a plain app password gets. It reads as a failure but is a
    /// permission, and the app has to say so in words people can act on.
    @Test("A credential without chat access produces an explanation")
    func explainsMissingPermission() async throws {
        StubTransport.reset([
            .init(status: 400, body: Data(#"""
            {"error":"InvalidRequest","message":"insufficient access to request a service auth token for the following method: chat.bsky.convo.listConvos"}
            """#.utf8))
        ])

        let client = makeClient()
        do {
            _ = try await client.conversations()
            Issue.record("expected the call to throw")
        } catch let error as ATProtoError {
            guard case .chatNotPermitted = error else {
                Issue.record("expected chatNotPermitted, got \(error)")
                return
            }
            let text = try #require(error.errorDescription)
            // The wording must name the fix, not the endpoint.
            #expect(!text.contains("chat.bsky.convo"))
            #expect(text.localizedCaseInsensitiveContains("app password")
                    || text.localizedCaseInsensitiveContains("app-passwort"))
        }
    }

    @Test("Other chat errors keep their own message")
    func otherErrorsPassThrough() async throws {
        StubTransport.reset([
            .init(status: 500, body: Data(#"{"error":"InternalServerError","message":"upstream failed"}"#.utf8))
        ])

        let client = makeClient()
        do {
            _ = try await client.conversations()
            Issue.record("expected the call to throw")
        } catch let error as ATProtoError {
            if case .chatNotPermitted = error {
                Issue.record("a server fault was mistaken for a permission")
            }
            #expect(error.errorDescription == "upstream failed")
        }
    }
}

@Suite("Profile refresh", .serialized)
@MainActor
struct ProfileRefreshTests {

    private let profileJSON = #"""
    {"did":"did:plc:anna","handle":"anna.example.com","displayName":"Anna Weiß",
     "followersCount":1284,"followsCount":342,"postsCount":2107}
    """#

    /// Refreshing has to renew both halves: the numbers in the header and the
    /// posts beneath them. Reloading only one leaves a profile that looks updated
    /// but is not.
    @Test("Refresh fetches the profile and its posts")
    func refreshesBoth() async throws {
        StubTransport.reset([
            .init(body: Data(profileJSON.utf8)),                     // initial profile
            .init(body: Data(#"{"feed":[],"cursor":null}"#.utf8)),   // initial posts
            .init(body: Data(profileJSON.utf8)),                     // refreshed profile
            .init(body: Data(#"{"feed":[],"cursor":null}"#.utf8))    // refreshed posts
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        let model = ProfileModel()
        await model.load(actor: "did:plc:anna", app: app)
        #expect(StubTransport.requests.count == 2)

        await model.refresh(actor: "did:plc:anna", app: app)

        let paths = StubTransport.requests.compactMap { $0.url?.path }
        #expect(paths.filter { $0.hasSuffix("getProfile") }.count == 2)
        #expect(paths.filter { $0.hasSuffix("getAuthorFeed") }.count == 2)
        #expect(model.profile?.followersCount == 1284)
    }

    /// A failed refresh must not blank a profile that was already on screen.
    @Test("A failed refresh keeps what was shown")
    func failureKeepsContent() async throws {
        StubTransport.reset([
            .init(body: Data(profileJSON.utf8)),
            .init(body: Data(#"{"feed":[],"cursor":null}"#.utf8)),
            .init(status: 500, body: Data(#"{"error":"InternalServerError"}"#.utf8)),
            .init(status: 500, body: Data(#"{"error":"InternalServerError"}"#.utf8))
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        let model = ProfileModel()
        await model.load(actor: "did:plc:anna", app: app)
        await model.refresh(actor: "did:plc:anna", app: app)

        #expect(model.profile?.handle == "anna.example.com")
    }
}

@Suite("Starting a conversation", .serialized)
struct NewConversationTests {

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test",
                      session: ATSession(accessJwt: "a", refreshJwt: "r", handle: "t.test",
                                         did: "did:plc:t", email: nil, service: "https://pds.test"),
                      configuration: StubTransport.configuration)
    }

    /// Asking for the conversation with someone returns the existing one if there
    /// is one — the service decides, the app does not have to look first.
    @Test("Opening a conversation asks the chat service for the members")
    func opensConversation() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"token":"chat-token"}"#.utf8)),
            .init(body: Data(#"""
            {"convo":{"id":"convo-1","rev":"1",
             "members":[{"did":"did:plc:t","handle":"t.test"},
                        {"did":"did:plc:other","handle":"other.test"}]}}
            """#.utf8))
        ])

        let client = makeClient()
        let convo = try await client.conversation(with: "did:plc:other")
        #expect(convo.id == "convo-1")

        let requests = StubTransport.requests
        #expect(requests[0].url?.query?.contains("aud=did:web:api.bsky.chat") == true)
        #expect(requests[1].url?.host == "api.bsky.chat")
        #expect(requests[1].url?.query?.contains("members=did:plc:other") == true)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer chat-token")
    }

    @Test("The other member is the one that is not me")
    func partnerSelection() throws {
        let json = #"""
        {"id":"c","rev":"1","members":[
          {"did":"did:plc:me","handle":"me.test","displayName":"Ich"},
          {"did":"did:plc:you","handle":"you.test","displayName":"Du"}]}
        """#
        let convo = try JSONDecoder().decode(Convo.self, from: Data(json.utf8))

        #expect(convo.partner(excluding: "did:plc:me")?.handle == "you.test")
        #expect(convo.partner(excluding: "did:plc:you")?.handle == "me.test")
        // A conversation with oneself still shows somebody rather than nothing.
        #expect(convo.partner(excluding: nil) != nil)
    }
}
