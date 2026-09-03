//
//  JetstreamTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

// MARK: - Firehose

@Suite("Firehose decoding")
struct JetstreamTests {

    /// Likes and reposts carry an object with a URI, follows a bare DID string.
    @Test("Subject decodes from both shapes")
    func subjectShapes() throws {
        let reference = #"{"subject":{"uri":"at://did:plc:a/app.bsky.feed.post/1","cid":"c"}}"#
        let plain = #"{"subject":"did:plc:target"}"#

        struct Wrapper: Decodable { let subject: SubjectValue }

        let asReference = try JSONDecoder().decode(Wrapper.self, from: Data(reference.utf8))
        #expect(asReference.subject.value == "at://did:plc:a/app.bsky.feed.post/1")

        let asString = try JSONDecoder().decode(Wrapper.self, from: Data(plain.utf8))
        #expect(asString.subject.value == "did:plc:target")
    }

    @Test("Each kind maps to its collection and back")
    func kindMapping() {
        for kind in [RadarEvent.Kind.post, .like, .repost, .follow] {
            #expect(RadarEvent.Kind(collection: kind.collection) == kind)
        }
        #expect(RadarEvent.Kind(collection: "app.bsky.graph.block") == nil)
        #expect(RadarStream.all.collections.count == 4)
        #expect(RadarStream.posts.carriesText)
        #expect(RadarStream.follows.carriesText == false)
    }

    @Test("A like points at the post it liked, a post at itself")
    func threadTargets() {
        let like = RadarEvent(did: "did:plc:a", rkey: "1", cid: nil, kind: .like, text: "",
                              subject: "at://did:plc:b/app.bsky.feed.post/9", langs: [],
                              hasMedia: false, createdAt: nil, receivedAt: Date())
        #expect(like.threadURI == "at://did:plc:b/app.bsky.feed.post/9")

        let post = RadarEvent(did: "did:plc:a", rkey: "1", cid: nil, kind: .post, text: "hi",
                              subject: nil, langs: ["en"], hasMedia: false,
                              createdAt: nil, receivedAt: Date())
        #expect(post.threadURI == "at://did:plc:a/app.bsky.feed.post/1")

        let follow = RadarEvent(did: "did:plc:a", rkey: "1", cid: nil, kind: .follow, text: "",
                                subject: "did:plc:b", langs: [], hasMedia: false,
                                createdAt: nil, receivedAt: Date())
        #expect(follow.threadURI == nil)
    }
}

