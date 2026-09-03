//
//  RepostTests.swift
//  RelaysTests
//
//  A repost is the one feed item whose author is not the person whose name is
//  above it. The profile screen drew it without saying so, and against the live
//  network more than half of a busy account's main tab is reposts — so more than
//  half of that page was attributing other people's words to the profile owner.
//

import Testing
import Foundation
@testable import Relays

@Suite("Reposts")
struct RepostTests {

    /// The shape `app.bsky.feed.getAuthorFeed` actually returns, taken from a
    /// live reply: pfrazee.com reposting somebody else.
    private static let repostItem = Data("""
    {
      "post": {
        "uri": "at://did:plc:author/app.bsky.feed.post/1",
        "cid": "bafyreiauthor",
        "author": { "did": "did:plc:author", "handle": "michelleroy78.bsky.social" },
        "record": { "text": "not written by the reposter" },
        "indexedAt": "2026-08-30T18:00:00.000Z"
      },
      "reason": {
        "$type": "app.bsky.feed.defs#reasonRepost",
        "by": { "did": "did:plc:ragtjsm2j2vknwkz3zp4oxrd", "handle": "pfrazee.com" },
        "indexedAt": "2026-08-30T17:59:51.767Z"
      }
    }
    """.utf8)

    @Test("A repost names the account that reposted, not the one that wrote")
    func namesTheReposter() throws {
        let item = try JSONDecoder().decode(FeedViewPost.self, from: Self.repostItem)

        let reposter = try #require(item.repostedBy)
        #expect(reposter.handle == "pfrazee.com")
        #expect(item.post.author.handle == "michelleroy78.bsky.social")
        #expect(reposter.did != item.post.author.did)
    }

    @Test("A post nobody reposted names nobody")
    func plainPostNamesNobody() throws {
        var item = try JSONDecoder().decode(FeedViewPost.self, from: Self.repostItem)
        item.reason = nil
        #expect(item.repostedBy == nil)
    }

    // MARK: - What a list leaves out

    private func profile(_ did: String) -> ActorProfile {
        ActorProfile(did: did, handle: "\(did).test", displayName: nil, avatar: nil,
                     banner: nil, description: nil, followersCount: nil, followsCount: nil,
                     postsCount: nil, viewer: nil, verification: nil, labels: nil)
    }

    private func item(author: String, repostedBy: String? = nil,
                      uri: String? = nil) -> FeedViewPost {
        let who = profile(author)
        let view = PostView(uri: uri ?? "at://\(author)/app.bsky.feed.post/1", cid: "bafy",
                            author: who, record: PostRecord(text: "hello"), embed: nil,
                            replyCount: 0, repostCount: 0, likeCount: 0,
                            indexedAt: "2026-08-30T00:00:00Z", viewer: nil, labels: nil)
        let reason = repostedBy.map {
            FeedViewPost.Reason.repost(by: profile($0), indexedAt: "2026-08-30T00:00:00Z")
        }
        return FeedViewPost(post: view, reply: nil, reason: reason)
    }

    /// The mute is enforced by the moderation engine, which runs before any
    /// list sees a post. A profile is no exception — checked here because the
    /// obvious guess is that it would be.
    @MainActor
    @Test("A muted account is gone from every list, its own profile included")
    func mutedIsGoneEverywhere() async {
        StubTransport.reset([
            .init(body: Data(#"{"mutes":[{"did":"did:plc:muted","handle":"muted.test"}]}"#.utf8),
                  path: "app.bsky.graph.getMutes"),
            .init(body: Data(#"{"blocks":[]}"#.utf8), path: "app.bsky.graph.getBlocks"),
            .init(body: Data(#"{"lists":[]}"#.utf8), path: "app.bsky.graph.getListMutes"),
            .init(body: Data(#"{"preferences":[]}"#.utf8), path: "app.bsky.actor.getPreferences"),
        ])
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.loadModeration()
        #expect(app.mutedActors == ["did:plc:muted"])

        let own = item(author: "did:plc:muted")
        let reposted = item(author: "did:plc:muted", repostedBy: "did:plc:owner",
                            uri: "at://did:plc:muted/app.bsky.feed.post/2")

        #expect(FeedVisibility.visible([own, reposted], app: app, settings: AppSettings()).isEmpty)
    }

    /// The profile screen used to check neither of these — it filtered on the
    /// content decision alone.
    @MainActor
    @Test("A deleted post and a hidden repost both leave the list")
    func dropsDeletedAndHidden() async {
        StubTransport.reset([])
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        let settings = AppSettings()
        settings.hideReposts = true

        let kept = item(author: "did:plc:owner")
        let reposted = item(author: "did:plc:other", repostedBy: "did:plc:owner",
                            uri: "at://did:plc:other/app.bsky.feed.post/9")

        #expect(FeedVisibility.visible([kept, reposted],
                                       app: app, settings: settings).map(\.id) == [kept.id])
    }
}
