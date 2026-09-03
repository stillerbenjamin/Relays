//
//  EmbeddedRecordTests.swift
//  RelaysTests
//
//  `app.bsky.embed.record#view` is a union of eight. The app read one of them
//  and drew the other seven as nothing — and a `viewNotFound` worse than
//  nothing, because every field of a quoted post is optional, so decoding one
//  always succeeded and the row drew an empty bordered box.
//
//  The three view shapes below were taken from live replies (author feeds of
//  emily.space and bsky.app); the rest follow the lexicon.
//

import Testing
import Foundation
@testable import Relays

@Suite("Embedded records")
struct EmbeddedRecordTests {

    private func embed(_ json: String) throws -> PostEmbed {
        try JSONDecoder().decode(PostEmbed.self, from: Data(json.utf8))
    }

    private func wrap(_ inner: String) -> String {
        #"{"$type":"app.bsky.embed.record#view","record":"# + inner + "}"
    }

    // MARK: - The four that are content

    /// Live shape, from a post quoting the "Astronomy" feed.
    @Test("A quoted feed generator names the feed, not nothing")
    func feed() throws {
        let decoded = try embed(wrap(#"""
        {
          "$type": "app.bsky.feed.defs#generatorView",
          "uri": "at://did:plc:jcoy7v3a2t4rcfdh6i4kza25/app.bsky.feed.generator/astro",
          "displayName": "Astronomy",
          "description": "Astronomy posts, from astronomers!",
          "likeCount": 9027,
          "creator": { "did": "did:plc:jcoy7v3a2t4rcfdh6i4kza25", "handle": "emily.space" }
        }
        """#))

        guard case .record(let record) = decoded, case .feed(let feed)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(feed.displayName == "Astronomy")
        #expect(feed.likeCount == 9027)
        #expect(feed.creator?.handle == "emily.space")
        #expect(decoded.isRenderable)
        // It is not a quoted post, and nothing may mistake it for one.
        #expect(decoded.quoted == nil)
    }

    /// Live shape. The basic view carries no name — it is inside the record.
    @Test("A quoted starter pack finds its name one level down")
    func starterPack() throws {
        let decoded = try embed(wrap(#"""
        {
          "$type": "app.bsky.graph.defs#starterPackViewBasic",
          "uri": "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.graph.starterpack/3lnl47wkftd2d",
          "joinedAllTimeCount": 17,
          "record": { "name": "NFL Conference Championships", "description": "Football posters" },
          "creator": { "did": "did:plc:z72i7hdynmk6r22z27h6tvur", "handle": "bsky.app" }
        }
        """#))

        guard case .record(let record) = decoded, case .starterPack(let pack)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(pack.name == "NFL Conference Championships")
        #expect(pack.joinedAllTimeCount == 17)
        #expect(decoded.isRenderable)
    }

    @Test("A quoted list keeps its size")
    func list() throws {
        let decoded = try embed(wrap(#"""
        {
          "$type": "app.bsky.graph.defs#listView",
          "uri": "at://did:plc:a/app.bsky.graph.list/1",
          "name": "Astronomers",
          "description": "People who look up",
          "listItemCount": 240,
          "purpose": "app.bsky.graph.defs#curatelist",
          "creator": { "did": "did:plc:a", "handle": "emily.space" }
        }
        """#))

        guard case .record(let record) = decoded, case .list(let list)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(list.name == "Astronomers")
        #expect(list.listItemCount == 240)
    }

    @Test("A quoted labeler is named by its creator")
    func labeler() throws {
        let decoded = try embed(wrap(#"""
        {
          "$type": "app.bsky.labeler.defs#labelerView",
          "uri": "at://did:plc:ar7c4by46qjdydhdevvrndac/app.bsky.labeler.service/self",
          "likeCount": 1200,
          "creator": { "did": "did:plc:ar7c4by46qjdydhdevvrndac", "handle": "moderation.bsky.app",
                       "displayName": "Bluesky Moderation Service" }
        }
        """#))

        guard case .record(let record) = decoded, case .labeler(let labeler)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(labeler.creator?.handle == "moderation.bsky.app")
        #expect(labeler.likeCount == 1200)
    }

    // MARK: - The three that explain an absence

    /// Live shape. This is the one that used to draw an empty box.
    @Test("A deleted post says so instead of leaving a box")
    func notFound() throws {
        let decoded = try embed(wrap(#"""
        {
          "$type": "app.bsky.embed.record#viewNotFound",
          "uri": "at://did:plc:dafp64pwxz4vw75yn4c636kc/app.bsky.feed.post/3ml5vqqa42s2n",
          "notFound": true
        }
        """#))

        guard case .record(let record) = decoded else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(record == .notFound)
        #expect(decoded.isRenderable)
        // Nothing to open: the post is gone.
        #expect(record?.uri == nil)
        #expect(decoded.quoted == nil)
    }

    /// The real shape: `app.bsky.feed.defs#blockedAuthor` is a DID and a viewer
    /// state. There is no handle in it — which is the whole story of the next
    /// two tests.
    private static let blockedQuote = #"""
    {
      "$type": "app.bsky.embed.record#viewBlocked",
      "uri": "at://did:plc:b/app.bsky.feed.post/1",
      "blocked": true,
      "author": { "did": "did:plc:b", "viewer": { "blockedBy": false, "blocking": "at://block/1" } }
    }
    """#

    @Test("A blocked quote keeps the DID it has, and does not ask for a handle")
    func blocked() throws {
        let decoded = try embed(wrap(Self.blockedQuote))

        guard case .record(let record) = decoded, case .blocked(let did)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(did == "did:plc:b")
        #expect(decoded.isRenderable)
    }

    /// Why the variant above was not merely invisible but fatal: `ActorProfile`
    /// requires a handle, `blockedAuthor` has none, and a present-but-malformed
    /// value throws rather than decoding to nil.
    @Test("A blocked author is not a profile, and never was")
    func blockedAuthorIsNotAProfile() {
        let json = Data(#"{"did":"did:plc:b","viewer":{"blockedBy":false}}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ActorProfile.self, from: json)
        }
        // The shape the app now reads instead.
        #expect((try? JSONDecoder().decode(BlockedAuthor.self, from: json))?.did == "did:plc:b")
    }

    /// The middle link in the chain: the old decoder read the union straight
    /// into a `QuotedPost`, and a `QuotedPost` cannot hold a blocked author
    /// either. `decodeIfPresent` returns nil for a missing value — not for a
    /// present one it cannot read.
    @Test("A blocked quote could never have been a QuotedPost")
    func quotedPostChokesOnIt() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(QuotedPost.self, from: Data(Self.blockedQuote.utf8))
        }
    }

    /// The reason this matters far past one embed. The quote used to be decoded
    /// straight into a `QuotedPost`, whose `author` is an `ActorProfile` — so the
    /// throw above escaped the embed, the post, the feed item and the response.
    /// One blocked quote anywhere on a page took the entire page with it.
    @Test("One blocked quote does not take the page down")
    func pageSurvivesABlockedQuote() throws {
        let page = #"""
        {
          "feed": [
            { "post": { "uri": "at://did:plc:a/app.bsky.feed.post/1", "cid": "bafy1",
                        "author": { "did": "did:plc:a", "handle": "first.example.com" },
                        "record": { "text": "before" }, "indexedAt": "2026-09-02T10:00:00Z",
                        "embed": { "$type": "app.bsky.embed.record#view",
                                   "record": \#(Self.blockedQuote) } } },
            { "post": { "uri": "at://did:plc:c/app.bsky.feed.post/2", "cid": "bafy2",
                        "author": { "did": "did:plc:c", "handle": "second.example.com" },
                        "record": { "text": "after" }, "indexedAt": "2026-09-02T10:01:00Z" } }
          ],
          "cursor": "next"
        }
        """#

        let response = try JSONDecoder().decode(FeedResponse.self, from: Data(page.utf8))
        #expect(response.feed.count == 2)
        #expect(response.feed[1].post.record.text == "after")
        #expect(response.cursor == "next")

        guard case .record(let record)? = response.feed[0].post.embed,
              case .blocked(let did)? = record else {
            Issue.record("the blocked quote did not survive")
            return
        }
        #expect(did == "did:plc:b")
    }

    /// The app writes postgates, so it can produce this state itself — and until
    /// now it could not display what it had caused.
    @Test("A detached quote says the author took it back")
    func detached() throws {
        let decoded = try embed(wrap(#"""
        {"$type":"app.bsky.embed.record#viewDetached","uri":"at://did:plc:c/app.bsky.feed.post/1","detached":true}
        """#))

        guard case .record(let record) = decoded else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(record == .detached)
        #expect(decoded.isRenderable)
    }

    // MARK: - The ninth thing

    @Test("Something the protocol has not invented yet draws nothing, quietly")
    func unknown() throws {
        let decoded = try embed(wrap(#"{"$type":"app.bsky.embed.record#viewSomethingNew"}"#))
        guard case .record(let record) = decoded else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(record == .unknown)
    }

    // MARK: - Round trip

    /// The feed cache writes these back and reads them again. A variant that
    /// does not survive the trip becomes a blank row on the next launch.
    @Test("Every variant survives the feed cache",
          arguments: [EmbeddedRecord.notFound, .detached,
                      .blocked(did: "did:plc:b"),
                      .feed(EmbeddedFeed(uri: "at://a", displayName: "Astronomy")),
                      .list(EmbeddedList(uri: "at://b", name: "Astronomers")),
                      .starterPack(EmbeddedStarterPack(uri: "at://c")),
                      .labeler(EmbeddedLabeler(uri: "at://d"))])
    func roundTrip(_ record: EmbeddedRecord) throws {
        let embed = PostEmbed.record(record)
        let data = try JSONEncoder().encode(embed)
        let back = try JSONDecoder().decode(PostEmbed.self, from: data)
        guard case .record(let returned) = back else {
            Issue.record("decoded as \(back)")
            return
        }
        #expect(returned == record)
    }
}
