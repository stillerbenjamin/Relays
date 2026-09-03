//
//  OwnSpaceTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

@Suite("Reply and quote rules")
struct OwnSpaceTests {

    // MARK: - Rules

    /// Taken from real records: pfrazee.com, why.bsky.team and esb.lol each use
    /// a different one of the three.
    @Test("Every rule the protocol writes is read back as itself")
    func ruleRoundTrip() throws {
        for rule in [ReplyRule.mentioned, .followed, .followers, .list(uri: "at://list/1")] {
            let encoded = try #require(rule.encoded)
            #expect(ReplyRule(decoded: encoded) == rule)
        }
        // These two are not rules but the absence of them.
        #expect(ReplyRule.everybody.encoded == nil)
        #expect(ReplyRule.nobody.encoded == nil)
    }

    @Test("A record decodes into the gate it describes")
    func decodesRecord() throws {
        let following = JSONValue.object([
            "$type": .string("app.bsky.feed.threadgate"),
            "post": .string("at://did:plc:a/app.bsky.feed.post/1"),
            "allow": .array([.object(["$type": .string("app.bsky.feed.threadgate#followingRule")])]),
        ])
        let gate = ATProtoClient.gate(from: following)
        #expect(gate.rules == [.followed])
        #expect(!gate.allowsEverybody)
        #expect(!gate.allowsNobody)

        // An empty allow list is the record for "nobody" — not a broken record.
        let closed = JSONValue.object([
            "$type": .string("app.bsky.feed.threadgate"),
            "allow": .array([]),
        ])
        #expect(ATProtoClient.gate(from: closed).allowsNobody)

        // No allow at all means everybody, even when replies are hidden.
        let hidden = JSONValue.object([
            "$type": .string("app.bsky.feed.threadgate"),
            "hiddenReplies": .array([.string("at://did:plc:b/app.bsky.feed.post/2")]),
        ])
        let open = ATProtoClient.gate(from: hidden)
        #expect(open.allowsEverybody)
        #expect(open.hiddenReplies.count == 1)
    }

    @Test("The notice says which of the three states a post is in")
    func summary() {
        #expect(ThreadGate().summary == nil)
        #expect(ThreadGate(rules: []).summary == L(.replyNobodyNotice))
        #expect(ThreadGate(rules: [.followed]).summary?.contains(ReplyRule.followed.label) == true)
    }

    @Test("A post's rules live at the post's own key")
    func sharedKey() {
        let uri = "at://did:plc:a/app.bsky.feed.post/3mtwf7gxkwc2r"
        #expect(ATProtoClient.rkey(of: uri) == "3mtwf7gxkwc2r")
    }

    // MARK: - Hidden posts

    @Test("A hidden post is hidden, and can be brought back")
    func hiddenPosts() {
        var preferences = Preferences()
        preferences.setHiddenPosts(["at://a/1", "at://a/2"])
        #expect(preferences.hiddenPostURIs.count == 2)

        preferences.setHiddenPosts(["at://a/1"])
        #expect(preferences.hiddenPostURIs == ["at://a/1"])
        #expect(preferences.entries.filter { $0.type == Preferences.hiddenPosts }.count == 1)
    }

    @Test("Hiding one post hides that post and nothing else")
    func hidingDecides() {
        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: nil,
                                  avatar: nil, banner: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil,
                                  verification: nil, labels: nil, associated: nil)
        func post(_ rkey: String) -> PostView {
            PostView(uri: "at://did:plc:a/app.bsky.feed.post/\(rkey)", cid: "c", author: author,
                     record: PostRecord(text: "hi"), embed: nil, replyCount: 0, repostCount: 0,
                     likeCount: 0, indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
        }

        let context = ModerationContext(hiddenPosts: ["at://did:plc:a/app.bsky.feed.post/1"],
                                        viewerDID: "did:plc:me")
        let decision = Moderation.decide(post: post("1"), context: context)
        #expect(decision.hides)
        #expect(decision.source == .hiddenPost)
        #expect(!Moderation.decide(post: post("2"), context: context).hides)
    }
}
