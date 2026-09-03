//
//  RelaysTests.swift
//  RelaysTests
//

import Testing
import UserNotifications
import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
@testable import Relays

// MARK: - Facets

/// Facets index UTF-8 bytes. Any post with an umlaut or an emoji before a link
/// breaks if the conversion slips, so these cases carry the weight.
@Suite("Rich text facets")
struct FacetTests {

    @Test("Plain text without facets stays one segment")
    func plainText() {
        let segments = RichText.segments(text: "hello world", facets: nil)
        #expect(segments.count == 1)
        if case .text(let value) = segments[0] {
            #expect(value == "hello world")
        } else {
            Issue.record("expected a text segment")
        }
    }

    @Test("Byte offsets survive multi-byte characters")
    func multiByteOffsets() {
        // "Grüße " is 8 bytes: G r ü(2) ß(2) e space
        let text = "Grüße https://example.com danach"
        let start = Array(text.utf8).count - Array(" danach".utf8).count - Array("https://example.com".utf8).count
        let facet = Facet(index: .init(byteStart: start,
                                       byteEnd: start + Array("https://example.com".utf8).count),
                          features: [.link(uri: "https://example.com")])

        let segments = RichText.segments(text: text, facets: [facet])
        let links = segments.compactMap { segment -> String? in
            if case .link(let value, _) = segment { return value }
            return nil
        }
        #expect(links == ["https://example.com"])
    }

    @Test("Emoji before a facet does not shift the slice")
    func emojiOffsets() {
        let prefix = "🚀 "
        let handle = "@alice.bsky.social"
        let text = prefix + handle
        let start = Array(prefix.utf8).count
        let facet = Facet(index: .init(byteStart: start, byteEnd: start + Array(handle.utf8).count),
                          features: [.mention(did: "did:plc:abc")])

        let segments = RichText.segments(text: text, facets: [facet])
        let mentions = segments.compactMap { segment -> String? in
            if case .mention(let value, _) = segment { return value }
            return nil
        }
        #expect(mentions == [handle])
    }

    @Test("Out-of-range facets are ignored rather than crashing")
    func brokenFacet() {
        let facet = Facet(index: .init(byteStart: 40, byteEnd: 90), features: [.link(uri: "https://x.example")])
        let segments = RichText.segments(text: "short", facets: [facet])
        #expect(segments.count == 1)
    }

    @Test("Composing detects links and hashtags with byte-accurate ranges")
    func detection() {
        let text = "Schöne Grüße https://example.com #test"
        let facets = RichText.detectFacets(in: text)
        let bytes = Array(text.utf8)

        #expect(facets.count == 2)
        for facet in facets {
            #expect(facet.index.byteStart >= 0)
            #expect(facet.index.byteEnd <= bytes.count)
            let slice = String(decoding: bytes[facet.index.byteStart..<facet.index.byteEnd], as: UTF8.self)
            switch facet.features.first {
            case .link: #expect(slice == "https://example.com")
            case .tag: #expect(slice == "#test")
            default: Issue.record("unexpected feature")
            }
        }
    }
}

// MARK: - Feed rules

@Suite("Feed rules")
@MainActor
struct FeedRuleTests {

    private func post(text: String, handle: String = "alice.bsky.social") -> FeedViewPost {
        let author = ActorProfile(did: "did:plc:test", handle: handle, displayName: nil,
                                  avatar: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil)
        let view = PostView(uri: "at://did:plc:test/app.bsky.feed.post/1", cid: "cid",
                            author: author, record: PostRecord(text: text), embed: nil,
                            replyCount: 0, repostCount: 0, likeCount: 0,
                            indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
        return FeedViewPost(post: view, reply: nil, reason: nil)
    }

    @Test("Keyword rules hide matching posts, case insensitively")
    func keyword() {
        let rules = FeedRules()
        rules.add(FeedRule(kind: .keyword, value: "spoiler"))
        #expect(rules.allows(post(text: "no spoilers here"), origin: nil) == false)
        #expect(rules.allows(post(text: "safe post"), origin: nil) == true)
        rules.rules.forEach(rules.remove)
    }

    @Test("Expired rules stop filtering")
    func expiry() {
        let rules = FeedRules()
        rules.add(FeedRule(kind: .keyword, value: "temporary",
                           expiresAt: Date().addingTimeInterval(-60)))
        #expect(rules.allows(post(text: "temporary noise"), origin: nil) == true)
        rules.rules.forEach(rules.remove)
    }

    @Test("Invalid patterns never filter anything")
    func brokenRegex() {
        #expect(FeedRules.isValidRegex("^GM ") == true)
        #expect(FeedRules.isValidRegex("([unclosed") == false)

        let rules = FeedRules()
        rules.add(FeedRule(kind: .regex, value: "([unclosed"))
        #expect(rules.allows(post(text: "anything"), origin: nil) == true)
        rules.rules.forEach(rules.remove)
    }

    @Test("Self-hosted rule keeps accounts with unknown origin")
    func selfHosted() {
        let rules = FeedRules()
        rules.add(FeedRule(kind: .selfHostedOnly, value: ""))
        #expect(rules.allows(post(text: "x"), origin: nil) == true)
        #expect(rules.allows(post(text: "x"), origin: AccountOrigin(host: "bsky.social")) == false)
        #expect(rules.allows(post(text: "x"), origin: AccountOrigin(host: "pds.example.com")) == true)
        rules.rules.forEach(rules.remove)
    }
}

// MARK: - Decoding

@Suite("Lexicon decoding")
struct DecodingTests {

    @Test("Video embeds decode from the view's own fields")
    func videoEmbed() throws {
        let json = """
        {"$type":"app.bsky.embed.video#view","cid":"bafy","playlist":"https://video.example/p.m3u8",
         "thumbnail":"https://video.example/t.jpg","alt":"a cat","aspectRatio":{"width":16,"height":9}}
        """
        let embed = try JSONDecoder().decode(PostEmbed.self, from: Data(json.utf8))
        guard case .video(let video) = embed else {
            Issue.record("expected a video embed")
            return
        }
        #expect(video.playlistURL?.absoluteString == "https://video.example/p.m3u8")
        #expect(video.alt == "a cat")
    }

    @Test("Records from other collections decode without text")
    func recordWithoutText() throws {
        let json = #"{"$type":"app.bsky.feed.like","createdAt":"2026-08-29T00:00:00Z"}"#
        let record = try JSONDecoder().decode(PostRecord.self, from: Data(json.utf8))
        #expect(record.text.isEmpty)
        #expect(record.createdAt != nil)
    }

    @Test("Saved feeds are picked out of mixed preferences")
    func preferences() throws {
        let json = """
        {"preferences":[
          {"$type":"app.bsky.actor.defs#adultContentPref","enabled":false},
          {"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[
            {"id":"1","type":"timeline","value":"following","pinned":true},
            {"id":"2","type":"feed","value":"at://did:plc:x/app.bsky.feed.generator/hot","pinned":true}]}
        ]}
        """
        let response = try JSONDecoder().decode(PreferencesResponse.self, from: Data(json.utf8))
        #expect(response.savedFeeds.count == 2)
        #expect(response.savedFeeds.last?.type == "feed")
    }

    @Test("Reposts stay distinct from the original in feed identity")
    func repostIdentity() throws {
        let json = """
        {"post":{"uri":"at://did:plc:a/app.bsky.feed.post/1","cid":"c","author":{"did":"did:plc:a","handle":"a.test"},
          "record":{"text":"hi"},"indexedAt":"2026-08-29T00:00:00Z"},
         "reason":{"$type":"app.bsky.feed.defs#reasonRepost","by":{"did":"did:plc:b","handle":"b.test"},
          "indexedAt":"2026-08-29T01:00:00Z"}}
        """
        let item = try JSONDecoder().decode(FeedViewPost.self, from: Data(json.utf8))
        #expect(item.id != item.post.uri)
        #expect(item.id.contains("repost"))
    }
}

// MARK: - Account origin

@Suite("Account origin")
struct OriginTests {

    @Test("Bluesky's own hosts are recognised")
    func blueskyHosts() {
        #expect(AccountOrigin(host: "bsky.social").isBlueskyHosted)
        #expect(AccountOrigin(host: "shimeji.us-east.host.bsky.network").isBlueskyHosted)
        #expect(AccountOrigin(host: "pds.example.com").isBlueskyHosted == false)
    }

    @Test("Long hosts shorten to their registrable part")
    func shortening() {
        #expect(AccountOrigin(host: "pds.someone.example.com").short == "example.com")
        #expect(AccountOrigin(host: "example.com").short == "example.com")
    }
}

// MARK: - Appearance

@Suite("Appearance")
@MainActor
struct AppearanceTests {

    /// The reported symptom was a theme switch that did not take effect at once.
    /// This pins the chain: setting the property applies the ground and bumps the
    /// token the interface is rebuilt on, synchronously.
    @Test("Choosing a ground applies immediately")
    func themeAppliesSynchronously() {
        let settings = AppSettings()
        let startingToken = settings.renderToken

        settings.theme = .dark
        #expect(Theme.theme == .dark)
        #expect(settings.renderToken == startingToken + 1)

        settings.theme = .blue
        #expect(Theme.theme == .blue)
        #expect(Theme.Palette.background == Theme.Palette.blueGround)
        #expect(settings.renderToken == startingToken + 2)
    }

    /// Every ground has to keep text, links and controls off the surface they sit
    /// on. The accent in particular shifts between light and dark for that reason.
    @Test("Each ground keeps its foreground colours distinct")
    func groundsRemainLegible() {
        let settings = AppSettings()

        for ground in AppTheme.allCases {
            settings.theme = ground
            #expect(Theme.Palette.textPrimary != Theme.Palette.background)
            #expect(Theme.Palette.textSecondary != Theme.Palette.background)
            #expect(Theme.Palette.link != Theme.Palette.background)
            #expect(Theme.Palette.accent != Theme.Palette.background)
            #expect(Theme.Palette.onAccent != Theme.Palette.accent)
            #expect(Theme.Palette.hairline != Theme.Palette.background)
        }

        settings.theme = .dark
    }

    @Test("Interaction colours stay apart from the accent")
    func interactionColours() {
        let settings = AppSettings()
        settings.theme = .dark
        #expect(Theme.Palette.like != Theme.Palette.accent)
        #expect(Theme.Palette.repost != Theme.Palette.accent)
        #expect(Theme.Palette.like != Theme.Palette.repost)
    }

    /// Inter ships in the bundle; if registration ever breaks, the interface
    /// silently falls back to the system face and nobody notices.
    @Test("Inter is registered and used for the interface")
    func interIsAvailable() {
        #expect(Theme.Font.hasInter)
        #expect(Bundle.main.url(forResource: "Inter-Regular", withExtension: "ttf") != nil)
        #expect(Bundle.main.url(forResource: "Inter-Medium", withExtension: "ttf") != nil)
    }

    @Test("Text size and slim weights feed into the type scale")
    func typeScale() {
        let settings = AppSettings()

        settings.textSize = .large
        #expect(Theme.Font.scale == TextSizeOption.large.scale)

        settings.textSize = .medium
        settings.slimFonts = false
        #expect(Theme.Font.slim == false)
        settings.slimFonts = true
        #expect(Theme.Font.slim)
    }
}

// Picture attachment is an iOS path — the picker, the renderer and the size
// budget are all UIKit. On macOS there is nothing here to test.
#if os(iOS)
// MARK: - Attaching images

@Suite("Image attachments")
@MainActor
struct ImageAttachmentTests {

    /// A picture with detail in it, so the encoder cannot compress it to nothing
    /// and the size limits are actually exercised.
    private func noisyImage(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for x in stride(from: 0, to: width, by: 8) {
                for y in stride(from: 0, to: height, by: 8) {
                    let shade = Double((x &* 31 &+ y &* 17) % 255) / 255
                    context.cgContext.setFillColor(red: shade, green: 1 - shade,
                                                   blue: Double((x &+ y) % 255) / 255, alpha: 1)
                    context.cgContext.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
        return image.pngData()!
    }

    @Test("Oversized pictures are scaled and compressed into budget")
    func largeImageFits() throws {
        let raw = noisyImage(width: 4000, height: 2250)
        let attachment = try #require(ImageAttachment.prepare(raw))

        #expect(attachment.byteCount <= 900_000)
        #expect(max(attachment.pixelSize.width, attachment.pixelSize.height) <= 2000)
        // 16:9 going in, 16:9 coming out.
        let ratio = attachment.pixelSize.width / attachment.pixelSize.height
        #expect(abs(ratio - 16.0 / 9.0) < 0.02)
    }

    @Test("Small pictures keep their size")
    func smallImageUntouched() throws {
        let raw = noisyImage(width: 800, height: 600)
        let attachment = try #require(ImageAttachment.prepare(raw))

        #expect(attachment.pixelSize.width == 800)
        #expect(attachment.pixelSize.height == 600)
        #expect(attachment.aspectRatio.width == 800)
        #expect(attachment.aspectRatio.height == 600)
    }

    @Test("Anything that is not an image is refused")
    func rejectsGarbage() {
        #expect(ImageAttachment.prepare(Data("not a picture".utf8)) == nil)
    }

    /// The lexicon's key names are easy to get wrong and the server simply
    /// refuses the record if they are.
    @Test("Blob and embed encode with the protocol's key names")
    func encoding() throws {
        let blob = BlobRef(ref: .init(link: "bafkreiabc"), mimeType: "image/jpeg", size: 4242)
        let embed = ATProtoClient.ImagesEmbed(images: [
            .init(image: blob, alt: "Ein Diagramm", aspectRatio: .init(width: 1600, height: 900))
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try #require(String(data: try encoder.encode(embed), encoding: .utf8))

        #expect(json.contains("\"$type\":\"app.bsky.embed.images\""))
        #expect(json.contains("\"$type\":\"blob\""))
        #expect(json.contains("\"$link\":\"bafkreiabc\""))
        #expect(json.contains("\"mimeType\":\"image\\/jpeg\"") || json.contains("\"mimeType\":\"image/jpeg\""))
        #expect(json.contains("\"alt\":\"Ein Diagramm\""))
        #expect(json.contains("\"aspectRatio\""))
    }
}
#endif

// MARK: - Hashtags

@Suite("Hashtags")
struct HashtagTests {

    /// Facets index UTF-8 bytes, so a tag after an umlaut is where offsets slip.
    @Test("Tags are detected with byte-accurate ranges")
    func detection() {
        let text = "Grüße aus Köln #atproto und #dezentral2026"
        let facets = RichText.detectFacets(in: text)
        let bytes = Array(text.utf8)

        let tags = facets.compactMap { facet -> String? in
            guard case .tag(let name)? = facet.features.first else { return nil }
            let slice = String(decoding: bytes[facet.index.byteStart..<facet.index.byteEnd], as: UTF8.self)
            #expect(slice == "#\(name)")
            return name
        }
        #expect(tags == ["atproto", "dezentral2026"])
    }

    @Test("A hash inside a word is not a tag")
    func noFalsePositives() {
        let facets = RichText.detectFacets(in: "C# und ##doppelt und foo#bar")
        let tags = facets.compactMap { facet -> String? in
            if case .tag(let name)? = facet.features.first { return name }
            return nil
        }
        #expect(tags.isEmpty)
    }

    @Test("Tags in plain text, such as bios, become segments")
    func bioTags() {
        let segments = RichText.autoLinkedSegments(in: "Schreibt über #atproto und #swift")
        let tags = segments.compactMap { segment -> String? in
            if case .tag(_, let name) = segment { return name }
            return nil
        }
        #expect(tags == ["atproto", "swift"])
    }

    @Test("Rendering a tagged post keeps the tag as its own segment")
    func rendering() {
        let text = "Läuft auf #atproto"
        let facets = RichText.detectFacets(in: text)
        let segments = RichText.segments(text: text, facets: facets)

        let tagSegments = segments.compactMap { segment -> String? in
            if case .tag(let value, _) = segment { return value }
            return nil
        }
        #expect(tagSegments == ["#atproto"])

        // The text around it survives intact.
        let plain = segments.compactMap { segment -> String? in
            if case .text(let value) = segment { return value }
            return nil
        }.joined()
        #expect(plain == "Läuft auf ")
    }
}

// MARK: - Mentions

@Suite("Mentions")
struct MentionTests {

    /// A handle needs a dot — "@alice" is a word, "@alice.bsky.social" is an account.
    @Test("Handles are recognised, bare words are not")
    func recognition() {
        let candidates = RichText.mentionCandidates(in: "Danke @maria.dev und @jay.bsky.team! Nicht @alice.")
        #expect(candidates.map(\.handle) == ["maria.dev", "jay.bsky.team"])
    }

    @Test("Trailing punctuation is not part of the handle")
    func punctuation() {
        let candidates = RichText.mentionCandidates(in: "cc @anna.example.com, @tom.test.")
        #expect(candidates.map(\.handle) == ["anna.example.com", "tom.test"])
    }

    @Test("Byte ranges survive umlauts and emoji")
    func byteRanges() {
        let text = "Grüße 🚀 @maria.dev"
        let candidates = RichText.mentionCandidates(in: text)
        let bytes = Array(text.utf8)

        let candidate = try? #require(candidates.first)
        let slice = String(decoding: bytes[candidate!.index.byteStart..<candidate!.index.byteEnd],
                           as: UTF8.self)
        #expect(slice == "@maria.dev")
    }

    @Test("An email address is not a mention")
    func noEmails() {
        let candidates = RichText.mentionCandidates(in: "Schreib an ben@example.com")
        #expect(candidates.isEmpty)
    }

    @Test("Mentions and links in one draft do not overlap")
    func mixedDraft() {
        let text = "@maria.dev siehe https://atproto.com #atproto"
        let facets = RichText.detectFacets(in: text)
        let mentions = RichText.mentionCandidates(in: text)

        // Detected facets (link, tag) must not sit inside the mention's range.
        let mention = try? #require(mentions.first)
        for facet in facets {
            let overlaps = facet.index.byteStart < mention!.index.byteEnd
                && mention!.index.byteStart < facet.index.byteEnd
            #expect(overlaps == false)
        }
        #expect(facets.count == 2)
    }
}

// MARK: - Moderation

@Suite("Moderation")
struct ModerationTests {

    /// The subject is a union: an account carries a DID, a post a URI and a CID.
    /// Getting the discriminator wrong means the report is silently dropped.
    @Test("Report subjects encode as the protocol expects")
    func subjectEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let account = try #require(String(data: try encoder.encode(ReportSubject.account(did: "did:plc:abc")),
                                         encoding: .utf8))
        #expect(account.contains("\"$type\":\"com.atproto.admin.defs#repoRef\""))
        #expect(account.contains("\"did\":\"did:plc:abc\""))
        #expect(!account.contains("uri"))

        let record = try #require(String(data: try encoder.encode(
            ReportSubject.record(uri: "at://did:plc:abc/app.bsky.feed.post/1", cid: "bafy")),
                                         encoding: .utf8))
        #expect(record.contains("\"$type\":\"com.atproto.repo.strongRef\""))
        #expect(record.contains("\"cid\":\"bafy\""))
        #expect(!record.contains("did\":"))
    }

    @Test("Every reason carries its lexicon identifier")
    func reasons() {
        #expect(ModerationReason.spam.rawValue == "com.atproto.moderation.defs#reasonSpam")
        #expect(ModerationReason.allCases.count == 6)
        for reason in ModerationReason.allCases {
            #expect(reason.rawValue.hasPrefix("com.atproto.moderation.defs#reason"))
            #expect(!reason.label.isEmpty)
        }
    }

    @MainActor
    @Test("Muting and blocking hide an account from the feeds")
    func hiding() {
        let app = AppModel()
        let profile = ActorProfile(did: "did:plc:loud", handle: "loud.test", displayName: nil,
                                   avatar: nil, banner: nil, description: nil,
                                   followersCount: nil, followsCount: nil, postsCount: nil,
                                   viewer: ActorViewerState(following: nil, followedBy: nil,
                                                            muted: true, blocking: nil))
        app.register(moderationOf: profile)

        #expect(app.isMuted("did:plc:loud"))
        #expect(app.isHidden("did:plc:loud"))
        #expect(app.isBlocked("did:plc:loud") == false)
        #expect(app.isHidden("did:plc:someone-else") == false)
    }
}

// MARK: - Localisation tables

@Suite("Localisation")
struct LocalisationTests {

    /// A duplicate key in a dictionary literal is a crash at launch, not a warning.
    /// This came up for real while moving strings between screens.
    @Test("Every declared key has text in both languages")
    func tablesAreComplete() {
        let gaps = L10n.keysWithoutText()
        #expect(gaps.isEmpty, "no text: \(gaps.joined(separator: ", "))")
    }

    /// Six English entries shipped with their German text still in them: the
    /// table was complete, so nothing complained, and an English interface said
    /// "Neue Nachricht". A present string is not a translated one.
    @Test("No entry is left in the other language")
    func tablesAreTranslated() {
        let wrong = L10n.keysInTheWrongLanguage()
        #expect(wrong.isEmpty, "wrong language: \(wrong.joined(separator: ", "))")
    }

    @Test("Both languages actually reach the interface")
    func switching() {
        L10n.language = .de
        #expect(L10n.t(.tabMessages) == "Nachrichten")
        #expect(L10n.t(.newMessage) == "Neue Nachricht")

        L10n.language = .en
        #expect(L10n.t(.tabMessages) == "Messages")
        #expect(L10n.t(.newMessage) == "New message")

        // `system` follows the device, and resolves to one of the two either way.
        #expect(AppLanguage.system.resolved != .system)
        L10n.language = .en
    }

    /// The app switches language on its own, independently of the device. A
    /// number formatted against the device locale reads "18.402" in an English
    /// interface on a German phone.
    @Test("Numbers follow the app language, not the device")
    func numbers() {
        L10n.language = .de
        #expect(Format.grouped(18402) == "18.402")
        #expect(Format.compact(1234) == "1,2k")
        #expect(Format.compact(2_400_000) == "2,4M")

        L10n.language = .en
        #expect(Format.grouped(18402) == "18,402")
        #expect(Format.compact(1234) == "1.2k")
        #expect(Format.compact(2_400_000) == "2.4M")

        // Below the threshold the number is written out, and the threshold moves
        // where a row has more space for it.
        #expect(Format.compact(999) == "999")
        #expect(Format.compact(9999, fullBelow: 10_000) == "9999")
        #expect(Format.compact(0) == "0")
    }

    @Test("Format strings carry their placeholder")
    func placeholders() {
        L10n.language = .en
        #expect(L10n.t(.feedRepostedBy, "Ada") == "Ada reposted")
        #expect(L10n.t(.hostedOn, "pds.example.com").contains("pds.example.com"))
        #expect(L10n.t(.rulesActive, 3).contains("3"))
    }
}

// MARK: - Verification

@Suite("Verification")
@MainActor
struct VerificationTests {

    private func profile(_ json: String) throws -> ActorProfile {
        try JSONDecoder().decode(ActorProfile.self, from: Data(json.utf8))
    }

    @Test("The two states are told apart")
    func states() throws {
        let verified = try profile(#"""
        {"did":"did:plc:a","handle":"a.test",
         "verification":{"verifiedStatus":"valid","trustedVerifierStatus":"none"}}
        """#)
        #expect(verified.verification?.isVerified == true)
        #expect(verified.verification?.isTrustedVerifier == false)

        let verifier = try profile(#"""
        {"did":"did:plc:b","handle":"b.test",
         "verification":{"verifiedStatus":"valid","trustedVerifierStatus":"valid"}}
        """#)
        #expect(verifier.verification?.isTrustedVerifier == true)
    }

    /// "invalid" is a claim that failed. It must not read as verified.
    @Test("A failed or absent verification shows nothing")
    func negativeStates() throws {
        let invalid = try profile(#"""
        {"did":"did:plc:c","handle":"c.test",
         "verification":{"verifiedStatus":"invalid","trustedVerifierStatus":"none"}}
        """#)
        #expect(invalid.verification?.isVerified == false)

        let plain = try profile(#"{"did":"did:plc:d","handle":"d.test"}"#)
        #expect(plain.verification == nil)
    }

    /// The badge takes the accent, which differs per ground — on the blue one it
    /// has to leave the background rather than disappear into it.
    @Test("The badge colour works on every ground")
    func colourPerTheme() {
        let settings = AppSettings()
        for ground in AppTheme.allCases {
            settings.theme = ground
            #expect(Theme.Palette.link != Theme.Palette.background)
        }
        settings.theme = .dark
    }
}

// MARK: - The tab bar

@Suite("Tapping the bar")
struct TabTapTests {

    @Test("A different tab switches to it")
    func switching() {
        #expect(TabTap.outcome(tapped: .profile, current: .timeline, isPushed: false)
                == .switchTo(.profile))
        // Even with something pushed on the tab being left.
        #expect(TabTap.outcome(tapped: .profile, current: .timeline, isPushed: true)
                == .switchTo(.profile))
    }

    /// A second tap has two meanings, and which one depends on whether there is
    /// something to come back from.
    @Test("The same tab pops first, and only then goes to the top")
    func reselecting() {
        #expect(TabTap.outcome(tapped: .timeline, current: .timeline, isPushed: true)
                == .popToRoot)
        #expect(TabTap.outcome(tapped: .timeline, current: .timeline, isPushed: false)
                == .backToTop)
    }

    @MainActor
    @Test("Going back to the top is counted, per tab")
    func counting() {
        let app = AppModel()
        #expect(app.reselects[.timeline] == nil)

        app.reselect(.timeline)
        app.reselect(.timeline)
        #expect(app.reselects[.timeline] == 2)
        // A screen watching its own tab is not woken by another one.
        #expect(app.reselects[.profile] == nil)

        app.reselect(.profile)
        #expect(app.reselects[.profile] == 1)
        #expect(app.reselects[.timeline] == 2)
    }
}

// MARK: - Which notifications are worth showing

@Suite("Notification delivery")
struct NotificationSelectionTests {

    /// Stands in for the settings: only the part the rule reads.
    private struct Kinds: NotificationKinds {
        var wanted: Set<String> = ["like", "repost", "follow", "reply", "mention", "quote"]
        func wantsNotification(ofKind reason: String) -> Bool { wanted.contains(reason) }
    }

    private func notification(_ reason: String, at stamp: String,
                              id: String = UUID().uuidString) -> ATNotification {
        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: "A",
                                  avatar: nil, banner: nil, description: nil,
                                  followersCount: nil, followsCount: nil, postsCount: nil,
                                  viewer: nil, verification: nil, labels: nil, associated: nil)
        return ATNotification(uri: "at://did:plc:a/app.bsky.feed.like/\(id)", cid: "c",
                              author: author, reason: reason, reasonSubject: nil,
                              isRead: false, indexedAt: stamp, record: nil)
    }

    private let since = ISO8601DateFormatter().date(from: "2026-08-30T12:00:00Z")!

    @MainActor
    @Test("Only what arrived since the last one the reader was told about")
    func onlyNewer() {
        let items = [
            notification("like", at: "2026-08-30T11:59:00Z"),   // before
            notification("like", at: "2026-08-30T12:00:00Z"),   // exactly then
            notification("like", at: "2026-08-30T12:01:00Z"),   // after
        ]
        let picked = NotificationService.selecting(from: items, settings: Kinds(), since: since)
        #expect(picked.count == 1)
    }

    @MainActor
    @Test("Kinds that were switched off do not arrive")
    func respectsKinds() {
        let items = [notification("like", at: "2026-08-30T12:05:00Z"),
                     notification("follow", at: "2026-08-30T12:06:00Z"),
                     notification("reply", at: "2026-08-30T12:07:00Z")]

        let onlyReplies = Kinds(wanted: ["reply"])
        let picked = NotificationService.selecting(from: items, settings: onlyReplies, since: since)
        #expect(picked.count == 1)
        #expect(picked.first?.0.reason == "reply")

        #expect(NotificationService.selecting(from: items, settings: Kinds(wanted: []),
                                              since: since).isEmpty)
    }

    /// Oldest first, so the newest ends up on top of the stack the system builds.
    @MainActor
    @Test("Delivered oldest first")
    func oldestFirst() {
        let items = [notification("like", at: "2026-08-30T12:09:00Z"),
                     notification("like", at: "2026-08-30T12:05:00Z"),
                     notification("like", at: "2026-08-30T12:07:00Z")]
        let picked = NotificationService.selecting(from: items, settings: Kinds(), since: since)
        #expect(picked.map { $0.1 } == picked.map { $0.1 }.sorted())
    }

    @MainActor
    @Test("A timestamp that cannot be read is not shown")
    func unreadableStamp() {
        let items = [notification("like", at: "not a date")]
        #expect(NotificationService.selecting(from: items, settings: Kinds(), since: since).isEmpty)
    }
}

@Suite("Notification presentation")
struct NotificationDelegateTests {

    /// The bug this guards: there was no delegate at all, so the system dropped
    /// every notification the app posted while it was in front — which is when
    /// it posts them.
    @MainActor
    @Test("The service makes itself the centre's delegate")
    func delegateIsInstalled() {
        let service = NotificationService()
        #expect(UNUserNotificationCenter.current().delegate === service)
    }

    /// `UNNotification` has no public initialiser, so the options themselves are
    /// what can be checked: a banner and a place in the list, not silence.
    @MainActor
    @Test("What it asks the system to do is show it")
    func presentationOptions() {
        #expect(NotificationService.foregroundPresentation.contains(.banner))
        #expect(NotificationService.foregroundPresentation.contains(.list))
        #expect(!NotificationService.foregroundPresentation.isEmpty)
    }
}
