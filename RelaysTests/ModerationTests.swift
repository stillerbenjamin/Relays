//
//  ModerationTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

// MARK: - Preferences

@Suite("Preferences round-trip")
struct PreferencesTests {

    /// What another client wrote has to survive a write from this one. The array
    /// is replaced whole, so an entry Relays drops is an entry the user loses.
    private let foreign = """
    {"preferences":[
      {"$type":"app.bsky.actor.defs#savedFeedsPrefV2","items":[{"id":"3k","type":"timeline","value":"following","pinned":true}]},
      {"$type":"app.bsky.actor.defs#personalDetailsPref","birthDate":"1991-04-02T00:00:00.000Z"},
      {"$type":"app.bsky.actor.defs#mutedWordsPref","items":[{"value":"spoiler","targets":["content"]}]},
      {"$type":"app.bsky.actor.defs#adultContentPref","enabled":true},
      {"$type":"app.bsky.actor.defs#contentLabelPref","label":"nudity","visibility":"warn"},
      {"$type":"app.bsky.actor.defs#threadViewPref","sort":"oldest","prioritizeFollowedUsers":true}
    ]}
    """

    private func load() throws -> Preferences {
        struct Response: Decodable { let preferences: [JSONValue] }
        let decoded = try JSONDecoder().decode(Response.self, from: Data(foreign.utf8))
        return Preferences(entries: decoded.preferences)
    }

    @Test("Entries this app does not model survive a write")
    func carriesUnknownEntries() throws {
        var preferences = try load()
        #expect(preferences.entries.count == 6)

        preferences.setAdultContent(false)
        preferences.setVisibility(.hide, for: "porn")

        let types = preferences.entries.compactMap(\.type)
        #expect(types.contains("app.bsky.actor.defs#savedFeedsPrefV2"))
        #expect(types.contains("app.bsky.actor.defs#personalDetailsPref"))
        #expect(types.contains("app.bsky.actor.defs#mutedWordsPref"))
        #expect(types.contains("app.bsky.actor.defs#threadViewPref"))

        // The birth date has to come back out exactly as it went in.
        let details = preferences.entries.first { $0.type == "app.bsky.actor.defs#personalDetailsPref" }
        #expect(details?.objectValue?["birthDate"]?.stringValue == "1991-04-02T00:00:00.000Z")
    }

    @Test("A whole number goes back out as a whole number")
    func integersStayIntegers() throws {
        // Encoded as a Double, 3 would come back as 3.0 and fail lexicon validation.
        let value = JSONValue.object(["count": .number(3), "ratio": .number(1.5)])
        let data = try JSONEncoder().encode(value)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("\"count\":3"))
        #expect(!text.contains("3.0"))
        #expect(text.contains("1.5"))
    }

    @Test("Setting a label twice leaves one entry")
    func visibilityIsReplaced() throws {
        var preferences = try load()
        preferences.setVisibility(.hide, for: "nudity")
        preferences.setVisibility(.ignore, for: "nudity")

        let entries = preferences.entries.filter {
            $0.objectValue?["label"]?.stringValue == "nudity"
        }
        #expect(entries.count == 1)
        #expect(preferences.visibility(for: "nudity", from: nil) == .ignore)

        // Removing it lets the definition's own default take over again.
        preferences.setVisibility(nil, for: "nudity")
        #expect(preferences.visibility(for: "nudity", from: nil) == nil)
    }

    @Test("A setting for one labeler does not leak to another")
    func perLabelerSettings() {
        var preferences = Preferences()
        preferences.setVisibility(.warn, for: "spam")
        preferences.setVisibility(.hide, for: "spam", from: "did:plc:strict")

        #expect(preferences.visibility(for: "spam", from: "did:plc:strict") == .hide)
        #expect(preferences.visibility(for: "spam", from: "did:plc:other") == .warn)
        #expect(preferences.visibility(for: "spam", from: nil) == .warn)
    }

    @Test("An empty preference array is not consent")
    func adultContentDefaultsOff() {
        #expect(Preferences().adultContentEnabled == false)
    }
}

// MARK: - The decision

@Suite("Moderation decisions")
struct ModerationDecisionTests {

    private func profile(_ did: String = "did:plc:author",
                         viewer: ActorViewerState? = nil,
                         labels: [ContentLabel] = []) -> ActorProfile {
        ActorProfile(did: did, handle: "a.example.com", displayName: nil, avatar: nil,
                     banner: nil, description: nil, followersCount: nil, followsCount: nil,
                     postsCount: nil, viewer: viewer, verification: nil,
                     labels: labels.isEmpty ? nil : labels)
    }

    private func post(author: ActorProfile, labels: [ContentLabel] = []) -> PostView {
        PostView(uri: "at://\(author.did)/app.bsky.feed.post/1", cid: "bafy", author: author,
                 record: PostRecord(text: "hello"), embed: nil, replyCount: 0, repostCount: 0,
                 likeCount: 0, indexedAt: "2026-08-29T00:00:00Z", viewer: nil,
                 labels: labels.isEmpty ? nil : labels)
    }

    private func label(_ value: String, from src: String = "did:plc:labeler") -> ContentLabel {
        ContentLabel(src: src, val: value, uri: nil)
    }

    private var adultOn: ModerationContext {
        var preferences = Preferences()
        preferences.setAdultContent(true)
        return ModerationContext(preferences: preferences, viewerDID: "did:plc:me")
    }

    @Test("Nothing labelled passes through untouched")
    func cleanPost() {
        let decision = Moderation.decide(post: post(author: profile()),
                                         context: ModerationContext())
        #expect(decision.verdict == .allow)
        #expect(decision.reason == nil)
    }

    @Test("A block outranks everything")
    func blocking() {
        let blocked = profile(viewer: ActorViewerState(blocking: "at://block/1"))
        let decision = Moderation.decide(post: post(author: blocked, labels: [label("spam")]),
                                         context: ModerationContext())
        #expect(decision.verdict == .hide)
        #expect(decision.source == .account)
    }

    @Test("Being blocked hides the other side too")
    func blockedBy() {
        let other = profile(viewer: ActorViewerState(blockedBy: true))
        #expect(Moderation.decide(post: post(author: other),
                                  context: ModerationContext()).verdict == .hide)
    }

    @Test("A mute through a list names the list")
    func mutedByList() {
        let viewer = ActorViewerState(mutedByList: ListRef(uri: "at://list/1", name: "Bots"))
        let decision = Moderation.decide(post: post(author: profile(viewer: viewer)),
                                         context: ModerationContext())
        #expect(decision.verdict == .hide)
        #expect(decision.reason?.contains("Bots") == true)
    }

    @Test("Sensitive content off hides an adult label whatever else was chosen")
    func adultContentOff() {
        var preferences = Preferences()
        preferences.setAdultContent(false)
        preferences.setVisibility(.ignore, for: "porn")
        let context = ModerationContext(preferences: preferences, viewerDID: "did:plc:me")

        let decision = Moderation.decide(post: post(author: profile(), labels: [label("porn")]),
                                         context: context)
        #expect(decision.verdict == .hide)
    }

    @Test("With sensitive content on, the per-label setting decides")
    func adultContentOn() {
        var preferences = Preferences()
        preferences.setAdultContent(true)
        preferences.setVisibility(.warn, for: "porn")
        let context = ModerationContext(preferences: preferences, viewerDID: "did:plc:me")

        // `porn` blurs the media, not the text.
        let decision = Moderation.decide(post: post(author: profile(), labels: [label("porn")]),
                                         context: context)
        #expect(decision.verdict == .blurMedia)
        #expect(decision.blursMedia)
        #expect(!decision.blursContent)
    }

    @Test("The strictest verdict wins, whatever order labels arrive in")
    func strictestWins() {
        let labels = [label("nudity"), label("!hide"), label("spam")]
        let reversed = Array(labels.reversed())

        let first = Moderation.decide(post: post(author: profile(), labels: labels),
                                      context: adultOn)
        let second = Moderation.decide(post: post(author: profile(), labels: reversed),
                                       context: adultOn)

        #expect(first.verdict == .hide)
        #expect(first.verdict == second.verdict)
        // Every label is kept, so the chips can still be drawn.
        #expect(Set(first.labels) == Set(["nudity", "!hide", "spam"]))
    }

    @Test("`!hide` cannot be switched off")
    func systemLabelIsNotConfigurable() {
        var preferences = Preferences()
        preferences.setAdultContent(true)
        preferences.setVisibility(.ignore, for: "!hide")
        let context = ModerationContext(preferences: preferences, viewerDID: "did:plc:me")

        #expect(Moderation.decide(post: post(author: profile(), labels: [label("!hide")]),
                                  context: context).verdict == .hide)
    }

    @Test("A label nobody defined is shown, but does not act")
    func unknownLabel() {
        let decision = Moderation.decide(post: post(author: profile(), labels: [label("substack")]),
                                         context: adultOn)
        #expect(decision.verdict == .badge)
        #expect(decision.labels == ["substack"])
    }

    @Test("A self-label is marked as the author's own")
    func selfLabel() {
        let author = profile()
        let decision = Moderation.decide(
            post: post(author: author, labels: [label("nudity", from: author.did)]),
            context: adultOn)
        #expect(decision.source == .selfLabel("nudity"))
    }

    @Test("A label on the author reaches their posts")
    func labelOnTheAccount() {
        let author = profile(labels: [label("!hide")])
        #expect(Moderation.decide(post: post(author: author), context: adultOn).verdict == .hide)
    }

    @Test("`!no-unauthenticated` means nothing to a reader who is signed in")
    func noUnauthenticated() {
        let author = profile(labels: [label("!no-unauthenticated")])
        #expect(Moderation.decide(post: post(author: author), context: adultOn).verdict == .allow)
    }

}

// MARK: - Against the model

@Suite("Moderation state", .serialized)
struct ModerationStateTests {

    private func profile(_ did: String, labels: [ContentLabel] = []) -> ActorProfile {
        ActorProfile(did: did, handle: "a.example.com", displayName: nil, avatar: nil,
                     banner: nil, description: nil, followersCount: nil, followsCount: nil,
                     postsCount: nil, viewer: nil, verification: nil,
                     labels: labels.isEmpty ? nil : labels)
    }

    private func post(author: ActorProfile) -> PostView {
        PostView(uri: "at://\(author.did)/app.bsky.feed.post/1", cid: "bafy", author: author,
                 record: PostRecord(text: "hello"), embed: nil, replyCount: 0, repostCount: 0,
                 likeCount: 0, indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
    }

    @MainActor
    @Test("Mutes, blocks and preferences arrive from the server")
    func loadsFromServer() async {
        StubTransport.reset([
            .init(body: Data(#"{"mutes":[{"did":"did:plc:m1","handle":"m1.test"}]}"#.utf8),
                  path: "app.bsky.graph.getMutes"),
            .init(body: Data(#"{"blocks":[{"did":"did:plc:b1","handle":"b1.test","viewer":{"blocking":"at://block/1"}}]}"#.utf8),
                  path: "app.bsky.graph.getBlocks"),
            .init(body: Data(#"{"lists":[{"uri":"at://list/1"}]}"#.utf8),
                  path: "app.bsky.graph.getListMutes"),
            .init(body: Data(#"{"preferences":[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]}"#.utf8),
                  path: "app.bsky.actor.getPreferences"),
        ])

        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.loadModeration()

        #expect(app.mutedActors == ["did:plc:m1"])
        #expect(app.blockedActors["did:plc:b1"] == "at://block/1")
        #expect(app.mutedLists == ["at://list/1"])
        #expect(app.preferences.adultContentEnabled)

        // A muted account is hidden even though nothing in the post says so —
        // that is the whole point of loading the list.
        #expect(app.decision(for: post(author: profile("did:plc:m1"))).hides)
    }

    @MainActor
    @Test("The reader's own writing is never moderated away from them")
    func ownPostsAreExempt() async {
        StubTransport.reset([])
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()

        let mine = profile("did:plc:tester", labels: [ContentLabel(src: "did:plc:l", val: "!hide", uri: nil)])
        let theirs = profile("did:plc:other", labels: [ContentLabel(src: "did:plc:l", val: "!hide", uri: nil)])

        #expect(app.decision(for: post(author: mine)).verdict == .allow)
        #expect(app.decision(for: post(author: theirs)).verdict == .hide)
    }

    @MainActor
    @Test("Uncovering is one step, and only where a step is offered")
    func revealing() async {
        StubTransport.reset([])
        let app = AppModel(configuration: StubTransport.configuration)
        await app.useTestSession()
        await app.setAdultContent(true)

        let covered = post(author: profile("did:plc:other"))
        let labelled = PostView(uri: covered.uri, cid: covered.cid, author: covered.author,
                                record: covered.record, embed: nil, replyCount: 0, repostCount: 0,
                                likeCount: 0, indexedAt: covered.indexedAt, viewer: nil,
                                labels: [ContentLabel(src: "did:plc:l", val: "nudity", uri: nil)])

        #expect(app.effectiveDecision(for: labelled).verdict == .blurMedia)
        app.toggleReveal(labelled.uri)
        #expect(app.effectiveDecision(for: labelled).verdict == .badge)
        app.toggleReveal(labelled.uri)
        #expect(app.effectiveDecision(for: labelled).verdict == .blurMedia)

        // Hidden is not revealable: no step past a block.
        let blocked = ActorProfile(did: "did:plc:blocked", handle: "b.test", displayName: nil,
                                   avatar: nil, banner: nil, description: nil, followersCount: nil,
                                   followsCount: nil, postsCount: nil,
                                   viewer: ActorViewerState(blocking: "at://block/1"),
                                   verification: nil, labels: nil)
        let hidden = post(author: blocked)
        app.toggleReveal(hidden.uri)
        #expect(app.effectiveDecision(for: hidden).verdict == .hide)
    }
}

// MARK: - Muted words

@Suite("Muted words")
struct MutedWordTests {

    private func post(_ text: String, tags: [String] = [],
                      author: String = "did:plc:other") -> PostView {
        // Tags travel as facets, so a real post carries them the way this does.
        let facets = tags.map { tag in
            Facet(index: .init(byteStart: 0, byteEnd: 0), features: [.tag(tag)])
        }
        let profile = ActorProfile(did: author, handle: "a.test", displayName: nil, avatar: nil,
                                   banner: nil, description: nil, followersCount: nil,
                                   followsCount: nil, postsCount: nil, viewer: nil,
                                   verification: nil, labels: nil, associated: nil)
        return PostView(uri: "at://\(author)/app.bsky.feed.post/1", cid: "c", author: profile,
                        record: PostRecord(text: text, createdAt: nil,
                                           facets: facets.isEmpty ? nil : facets),
                        embed: nil, replyCount: 0, repostCount: 0, likeCount: 0,
                        indexedAt: "2026-08-29T00:00:00Z", viewer: nil, labels: nil)
    }

    private func context(_ words: [MutedWord], following: Set<String> = []) -> ModerationContext {
        var preferences = Preferences()
        preferences.setMutedWords(words)
        return ModerationContext(preferences: preferences, following: following,
                                 viewerDID: "did:plc:me")
    }

    @Test("A word matches whole words, not pieces of them")
    func wholeWords() {
        let art = context([MutedWord(value: "art")])

        #expect(Moderation.decide(post: post("look at my art"), context: art).hides)
        #expect(Moderation.decide(post: post("Art is fine"), context: art).hides)
        #expect(Moderation.decide(post: post("art, actually"), context: art).hides)
        // The trap: muting "art" must not take "start" or "artist" with it.
        #expect(!Moderation.decide(post: post("let's start"), context: art).hides)
        #expect(!Moderation.decide(post: post("she is an artist"), context: art).hides)
    }

    @Test("Several words match as a sequence")
    func phrases() {
        let spoiler = context([MutedWord(value: "season finale")])

        #expect(Moderation.decide(post: post("the season finale was wild"), context: spoiler).hides)
        #expect(!Moderation.decide(post: post("finale of the season"), context: spoiler).hides)
        #expect(!Moderation.decide(post: post("season two"), context: spoiler).hides)
    }

    @Test("Targets decide where a word counts")
    func targets() {
        let tagOnly = context([MutedWord(value: "spoiler", targets: [.tag])])
        #expect(Moderation.decide(post: post("no warning", tags: ["spoiler"]),
                                  context: tagOnly).hides)
        #expect(!Moderation.decide(post: post("this is a spoiler"), context: tagOnly).hides)

        let textOnly = context([MutedWord(value: "spoiler", targets: [.content])])
        #expect(Moderation.decide(post: post("this is a spoiler"), context: textOnly).hides)
        #expect(!Moderation.decide(post: post("nothing", tags: ["spoiler"]),
                                   context: textOnly).hides)
    }

    @Test("A word can spare the accounts one follows")
    func excludeFollowing() {
        let friend = "did:plc:friend"
        let muted = context([MutedWord(value: "politics", scope: .excludeFollowing)],
                            following: [friend])

        #expect(Moderation.decide(post: post("politics again"), context: muted).hides)
        #expect(!Moderation.decide(post: post("politics again", author: friend),
                                   context: muted).hides)
    }

    @Test("An expired word stops working on its own")
    func expiry() {
        let over = MutedWord(value: "advent", expiresAt: Date().addingTimeInterval(-60))
        let running = MutedWord(value: "advent", expiresAt: Date().addingTimeInterval(3600))

        #expect(!Moderation.decide(post: post("advent"), context: context([over])).hides)
        #expect(Moderation.decide(post: post("advent"), context: context([running])).hides)
        #expect(over.isExpired)
        #expect(!running.isExpired)
    }

    @Test("The reason names the word that did it")
    func reason() {
        let decision = Moderation.decide(post: post("free crypto"),
                                         context: context([MutedWord(value: "crypto")]))
        #expect(decision.source == .mutedWord("crypto"))
        #expect(decision.reason?.contains("crypto") == true)
    }

    @Test("A running word shows what is left of it, not how long ago it started")
    func remaining() {
        // Against the unit strings rather than literals: another suite may have
        // switched the language, and this is not a test about wording.
        #expect(RelativeTime.remaining(until: Date().addingTimeInterval(6 * 86_400))
                == "6\(L10n.t(.timeDay))")
        #expect(RelativeTime.remaining(until: Date().addingTimeInterval(3 * 3600))
                == "3\(L10n.t(.timeHour))")
        // The compact formatter clamps the past, so a future date came out of it
        // as "now" until this had its own direction.
        #expect(RelativeTime.remaining(until: Date().addingTimeInterval(-60)) == L10n.t(.timeNow))
    }

    @Test("Words survive the trip through the preferences record")
    func roundTrip() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        var preferences = Preferences()
        preferences.setMutedWords([
            MutedWord(id: "one", value: "spoiler", targets: [.tag], scope: .excludeFollowing,
                      expiresAt: expiry),
            MutedWord(id: "two", value: "two words"),
        ])

        let read = preferences.mutedWordList
        #expect(read.count == 2)
        #expect(read[0].value == "spoiler")
        #expect(read[0].targets == [.tag])
        #expect(read[0].scope == .excludeFollowing)
        #expect(abs((read[0].expiresAt ?? .distantPast).timeIntervalSince(expiry)) < 1)
        #expect(read[1].targets == [.content, .tag])
        #expect(read[1].expiresAt == nil)

        // And still only one entry in the array.
        #expect(preferences.entries.filter { $0.type == Preferences.mutedWords }.count == 1)
    }
}
