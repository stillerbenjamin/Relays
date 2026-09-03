//
//  PostListTests.swift
//  RelaysTests
//
//  The quote counter has led somewhere for a while. The like and repost counters
//  led nowhere at all — the numbers were the end of the road.
//
//  The two replies do not have the same shape, and one decoder over both would
//  quietly return an empty list for one of them:
//
//      getLikes      → { "likes":      [ { "actor": {…} , "createdAt": … } ] }
//      getRepostedBy → { "repostedBy": [ {…} ] }
//

import Testing
import Foundation
@testable import Relays

@MainActor
@Suite("Post lists", .serialized)
struct PostListTests {

    private let uri = "at://did:plc:author/app.bsky.feed.post/1"

    /// A signed-in client: both endpoints go through the authenticated path.
    private func client() async -> ATProtoClient {
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        return app.client
    }

    @Test("A like carries its account one level down")
    func likes() async throws {
        StubTransport.reset([
            .init(body: Data(#"""
            {"likes":[
              {"createdAt":"2026-09-01T10:00:00Z",
               "actor":{"did":"did:plc:a","handle":"first.example.com","displayName":"First"}},
              {"createdAt":"2026-09-01T10:01:00Z",
               "actor":{"did":"did:plc:b","handle":"second.example.com"}}],
             "cursor":"next"}
            """#.utf8), path: "app.bsky.feed.getLikes")
        ])

        let page = try await (await client()).likes(of: uri)
        #expect(page.actors.map(\.handle) == ["first.example.com", "second.example.com"])
        #expect(page.actors.first?.displayName == "First")
        #expect(page.cursor == "next")
    }

    @Test("A repost is the account itself")
    func reposts() async throws {
        StubTransport.reset([
            .init(body: Data(#"""
            {"repostedBy":[{"did":"did:plc:c","handle":"third.example.com"}],"cursor":null}
            """#.utf8), path: "app.bsky.feed.getRepostedBy")
        ])

        let page = try await (await client()).repostedBy(uri: uri)
        #expect(page.actors.map(\.handle) == ["third.example.com"])
        #expect(page.cursor == nil)
    }

    /// Proof that the two shapes are really different: the reply one endpoint
    /// sends decodes to nothing at the other.
    @Test("The two shapes are not interchangeable")
    func shapesDiffer() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"repostedBy":[{"did":"did:plc:c","handle":"third.example.com"}]}"#.utf8),
                  path: "app.bsky.feed.getLikes")
        ])
        await #expect(throws: (any Error).self) {
            _ = try await (await self.client()).likes(of: self.uri)
        }
    }

    @Test("The post travels as the subject, and the page size with it")
    func requestShape() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"likes":[]}"#.utf8), path: "app.bsky.feed.getLikes")
        ])
        _ = try await (await client()).likes(of: uri, cursor: "page2", limit: 25)

        let request = try #require(StubTransport.requests.last)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        #expect(value("uri") == uri)
        #expect(value("limit") == "25")
        #expect(value("cursor") == "page2")
    }

    /// The subject of these two lists is a post, not an account — which is why
    /// the screen's parameter is no longer called `actor`.
    @Test("Each kind knows what its subject is")
    func subjects() {
        #expect(ActorListKind.likes.subjectIsPost)
        #expect(ActorListKind.reposts.subjectIsPost)
        #expect(!ActorListKind.followers.subjectIsPost)
        #expect(!ActorListKind.following.subjectIsPost)
    }
}

/// Both endpoints are public — no account, only a network.
@Suite("Post lists against the live network",
       .disabled("Needs the network; run by hand after touching the counters"))
struct PostListLiveTests {

    private func fetch(_ endpoint: String, uri: String) async throws -> Data {
        var components = try #require(URLComponents(string:
            "https://public.api.bsky.app/xrpc/\(endpoint)"))
        components.queryItems = [URLQueryItem(name: "uri", value: uri),
                                 URLQueryItem(name: "limit", value: "5")]
        let (data, response) = try await URLSession.shared.data(from: try #require(components.url))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return data
    }

    /// A post that both lists answer for, found through a public author feed.
    private func aPost() async throws -> String {
        let url = try #require(URL(string: "https://public.api.bsky.app/xrpc/"
            + "app.bsky.feed.getAuthorFeed?actor=bsky.app&limit=20&filter=posts_no_replies"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let feed = try JSONDecoder().decode(FeedResponse.self, from: data)
        let liked = try #require(feed.feed.first { ($0.post.likeCount ?? 0) > 0 })
        return liked.post.uri
    }

    @Test("Both lists answer, and each in its own shape")
    func bothAnswer() async throws {
        let uri = try await aPost()

        struct Likes: Decodable { struct Like: Decodable { let actor: ActorProfile }
                                  let likes: [Like] }
        struct Reposts: Decodable { let repostedBy: [ActorProfile] }

        let likes = try JSONDecoder().decode(Likes.self,
                                             from: try await fetch("app.bsky.feed.getLikes", uri: uri))
        #expect(!likes.likes.isEmpty)
        #expect(likes.likes.allSatisfy { !$0.actor.handle.isEmpty })

        // Reposts may genuinely be zero; the shape is what is under test.
        _ = try JSONDecoder().decode(Reposts.self,
                                     from: try await fetch("app.bsky.feed.getRepostedBy", uri: uri))
    }
}
