//
//  QuoteTests.swift
//  RelaysTests
//
//  Quoting leaves two marks: the quoted post appears inside the new one, and the
//  count on the quoted post moves. Both were missing.
//

import Testing
import Foundation
@testable import Relays

@Suite("Quotes")
struct QuoteTests {

    /// Trimmed from what the appview actually returned for a real quote post.
    private let plainQuote = """
    {"$type":"app.bsky.embed.record#view",
     "record":{"$type":"app.bsky.embed.record#viewRecord",
       "uri":"at://did:plc:wbmw5r5a2j7txv72ggne2uoe/app.bsky.feed.post/3mtzkm3hmo222",
       "cid":"bafyreiann2hbjkoilj44cz4b7fntuoj6b5rb2ha5xlpc2iilbnujvv54pu",
       "author":{"did":"did:plc:wbmw5r5a2j7txv72ggne2uoe","handle":"cpsc.gov",
                 "displayName":"U.S. Consumer Product Safety Commission"},
       "value":{"$type":"app.bsky.feed.post","createdAt":"2026-08-27T00:08:52.368Z",
                "text":"Beats to Relax and be safe to"},
       "likeCount":12,"replyCount":1,"repostCount":3,"quoteCount":0}}
    """

    /// The shape that used to lose the quote: the quoted post sits one level
    /// deeper, under `record.record`, and the media sits beside it.
    private let quoteWithPicture = """
    {"$type":"app.bsky.embed.recordWithMedia#view",
     "media":{"$type":"app.bsky.embed.images#view",
       "images":[{"thumb":"https://cdn.example/t.jpg","fullsize":"https://cdn.example/f.jpg",
                  "alt":"you are a star, baby","aspectRatio":{"height":600,"width":600}}]},
     "record":{"record":{"$type":"app.bsky.embed.record#viewRecord",
       "uri":"at://did:plc:yk4dd2qkboz2yv6tpubpc6co/app.bsky.feed.post/3mu3vn7dge22t",
       "cid":"bafyreifpasjpcgbjcg4yinlzvb7st7h3om2pt7e3mwuweofw27deqd634q",
       "author":{"did":"did:plc:yk4dd2qkboz2yv6tpubpc6co","handle":"dholms.at",
                 "displayName":"daniel holmgren"},
       "value":{"$type":"app.bsky.feed.post","createdAt":"2026-08-27T22:31:40.616Z",
                "text":"the post being quoted"}}}}
    """

    private func embed(_ json: String) throws -> PostEmbed {
        try JSONDecoder().decode(PostEmbed.self, from: Data(json.utf8))
    }

    @Test("A plain quote carries the post it points at")
    func plain() throws {
        let decoded = try embed(plainQuote)
        guard case .record(let record) = decoded, case .post(let quoted)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(quoted.author?.handle == "cpsc.gov")
        #expect(quoted.value?.text == "Beats to Relax and be safe to")
        #expect(decoded.isRenderable)
    }

    /// This one used to come out as a picture with the quote thrown away, so a
    /// quote with an image attached showed no sign of being a quote at all.
    @Test("A quote with a picture keeps both halves")
    func withMedia() throws {
        let decoded = try embed(quoteWithPicture)
        guard case .recordWithMedia(let media, let record) = decoded,
              case .post(let quoted)? = record else {
            Issue.record("decoded as \(decoded)")
            return
        }
        #expect(quoted.author?.handle == "dholms.at")
        #expect(quoted.value?.text == "the post being quoted")
        #expect(decoded.isRenderable)

        guard case .images(let images) = media else {
            Issue.record("media decoded as \(media)")
            return
        }
        #expect(images.count == 1)
        #expect(images.first?.alt == "you are a star, baby")

        // `quoted` reaches the quoted post whichever shape carried it.
        #expect(decoded.quoted?.author?.handle == "dholms.at")
        #expect(try embed(plainQuote).quoted?.author?.handle == "cpsc.gov")
    }

    @Test("A quote survives the trip through the feed cache")
    func roundTrip() throws {
        let decoded = try embed(quoteWithPicture)
        let written = try JSONEncoder().encode(decoded)
        let read = try JSONDecoder().decode(PostEmbed.self, from: written)

        #expect(read.quoted?.author?.handle == "dholms.at")
        #expect(read.isRenderable)
    }

    // MARK: - The count on the quoted post

    private func post(quotes: Int, reposts: Int) -> PostView {
        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: nil,
                                  avatar: nil, banner: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil,
                                  verification: nil, labels: nil, associated: nil)
        return PostView(uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "c", author: author,
                        record: PostRecord(text: "hi"), embed: nil, replyCount: 0,
                        repostCount: reposts, likeCount: 0, quoteCount: quotes,
                        indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
    }

    @Test("The repost control counts quotes as well as reposts")
    func sharedCount() {
        #expect(PostState(post: post(quotes: 4, reposts: 7)).sharedCount == 11)
        #expect(PostState(post: post(quotes: 0, reposts: 0)).sharedCount == 0)
    }

    @MainActor
    @Test("Quoting moves the number on the post that was quoted")
    func quotingMovesTheCount() async {
        StubTransport.reset([])
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        let quoted = post(quotes: 2, reposts: 5)
        app.register([quoted])
        #expect(app.state(for: quoted).sharedCount == 7)

        app.noteQuoteAdded(to: quoted.uri)
        #expect(app.state(for: quoted).quoteCount == 3)
        #expect(app.state(for: quoted).sharedCount == 8)
    }
}
