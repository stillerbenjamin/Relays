//
//  LinkCardTests.swift
//  RelaysTests
//
//  The app could draw link cards from the first day and never made one. A link
//  posted from Relays arrived as bare text while the same link from any other
//  client arrived as a card — and nothing said so, because reading and writing
//  are different halves and only one was built.
//

import Testing
import Foundation
@testable import Relays

@Suite("Link cards")
struct LinkCardTests {

    private let page = URL(string: "https://example.com/a/b")!

    @Test("Open Graph is read first, because it was written for this")
    func openGraph() {
        let html = """
        <html><head>
        <title>Ignore me</title>
        <meta property="og:title" content="The real title">
        <meta property="og:description" content="What the page is about">
        <meta property="og:image" content="https://example.com/card.png">
        </head><body>…</body></html>
        """
        let card = LinkCardReader.card(from: html, url: page)
        #expect(card.title == "The real title")
        #expect(card.description == "What the page is about")
        #expect(card.imageURL?.absoluteString == "https://example.com/card.png")
        #expect(card.isWorthShowing)
    }

    /// Attributes come in either order and under either spelling in the wild.
    /// The apostrophe is the point: a `["\']` closing class ends the match
    /// there, whatever quote actually opened it.
    @Test("`name=`, a reversed order, and an apostrophe inside the value")
    func spellings() {
        let html = """
        <meta name="twitter:title" content="From Twitter's names">
        <meta content="Reversed order" property="og:description">
        <meta property='og:site_name' content='Single quoted'>
        """
        let card = LinkCardReader.card(from: html, url: page)
        #expect(card.title == "From Twitter's names")
        #expect(card.description == "Reversed order")
        #expect(LinkCardReader.card(from: "<meta property='og:title' content='Single \"quoted\"'>",
                                    url: page).title == "Single \"quoted\"")
    }

    @Test("A page with no tags still makes a card from its title")
    func plainPage() {
        let card = LinkCardReader.card(from: "<html><head><title>Just a title</title></head>",
                                        url: page)
        #expect(card.title == "Just a title")
        #expect(card.imageURL == nil)
        #expect(card.isWorthShowing)
    }

    @Test("A page that says nothing about itself is not worth a card")
    func nothingToSay() {
        #expect(!LinkCardReader.card(from: "<html><body>hello</body></html>", url: page)
            .isWorthShowing)
    }

    /// A relative image path is legal and common. Resolving it against the page
    /// is the difference between a card and a broken one.
    @Test("A relative picture is resolved against the page it came from",
          arguments: [("/card.png", "https://example.com/card.png"),
                      ("card.png", "https://example.com/a/card.png"),
                      ("//cdn.example.com/c.png", "https://cdn.example.com/c.png"),
                      ("https://other.example/c.png", "https://other.example/c.png")])
    func relativeImages(_ given: String, _ expected: String) {
        let html = #"<meta property="og:image" content=""# + given + #"">"#
        #expect(LinkCardReader.card(from: html, url: page).imageURL?.absoluteString == expected)
    }

    @Test("Entities in a title are turned back into characters")
    func entities() {
        let html = #"<meta property="og:title" content="Tools &amp; Toys &mdash; a &quot;list&quot;">"#
        #expect(LinkCardReader.card(from: html, url: page).title == "Tools & Toys — a \"list\"")
    }

    // MARK: - Which link gets the card

    @Test("The first link in the text is the one that gets a card")
    func firstLink() {
        let text = "See https://one.example.com and also https://two.example.com"
        #expect(LinkCardReader.firstLink(in: text)?.absoluteString == "https://one.example.com")
    }

    @Test("Text with no link asks for nothing")
    func noLink() {
        #expect(LinkCardReader.firstLink(in: "nothing to see here") == nil)
        #expect(LinkCardReader.firstLink(in: "") == nil)
    }

    /// A card is one of the things a post can carry, and a post carries one.
    /// Anything the author attached on purpose outranks a card the app offered.
    @Test("The author's own attachment beats the app's suggestion")
    func embedPrecedence() throws {
        let blob = BlobRef(ref: .init(link: "bafy"), mimeType: "image/jpeg", size: 1)
        let images = ATProtoClient.ImagesEmbed(images: [.init(image: blob, alt: "", aspectRatio: nil)])
        let link = ATProtoClient.ExternalEmbed(
            external: .init(uri: "https://example.com", title: "T", description: "D", thumb: nil))
        let quote = StrongRef(uri: "at://a/app.bsky.feed.post/1", cid: "bafy")

        func typeOf(_ payload: ATProtoClient.PostEmbedPayload?) throws -> String {
            let data = try JSONEncoder().encode(payload)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try #require(json["$type"] as? String)
        }

        // With pictures, or a quote, the link steps aside.
        #expect(try typeOf(.make(images: images, quoting: nil, link: link))
                == "app.bsky.embed.images")
        #expect(try typeOf(.make(images: nil, quoting: quote, link: link))
                == "app.bsky.embed.record")
        // On its own it is the embed.
        #expect(try typeOf(.make(images: nil, quoting: nil, link: link))
                == "app.bsky.embed.external")
        // And nothing at all stays nothing.
        #expect(ATProtoClient.PostEmbedPayload.make(images: nil, quoting: nil, link: nil) == nil)
    }

    @Test("The embed is shaped the way the lexicon asks")
    func wireShape() throws {
        let embed = ATProtoClient.ExternalEmbed(
            external: .init(uri: "https://example.com", title: "Title",
                            description: "Description", thumb: nil))
        let json = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(embed)) as? [String: Any])

        #expect(json["$type"] as? String == "app.bsky.embed.external")
        let external = try #require(json["external"] as? [String: Any])
        #expect(external["uri"] as? String == "https://example.com")
        #expect(external["title"] as? String == "Title")
        #expect(external["description"] as? String == "Description")
        // A card without a picture omits the key rather than sending null.
        #expect(external["thumb"] == nil)
    }
}

/// Against the real thing: the project's own site, which carries the tags this
/// reader was written for.
@Suite("Link cards against the live network",
       .disabled("Needs the network; run by hand after touching the reader"))
struct LinkCardLiveTests {

    @Test("The project's own page reads as a card")
    func ownSite() async throws {
        let url = try #require(URL(string: "https://stillerbenjamin.github.io/Relays/"))
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; Relays/1.0)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = try #require(String(data: data, encoding: .utf8))

        let card = LinkCardReader.card(from: html, url: url)
        #expect(card.title == "Relays")
        #expect(card.description?.contains("Bluesky client") == true)
        #expect(card.imageURL?.absoluteString
                == "https://stillerbenjamin.github.io/Relays/preview.png")

        // And the picture it names actually answers.
        let (_, response) = try await URLSession.shared.data(from: try #require(card.imageURL))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }
}
