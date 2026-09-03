//
//  LabelerTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

@Suite("Labeler services")
struct LabelerTests {

    /// Shortened from what moderation.bsky.app actually answers.
    private let payload = """
    {"views":[{
      "$type":"app.bsky.labeler.defs#labelerViewDetailed",
      "uri":"at://did:plc:mod/app.bsky.labeler.service/self",
      "creator":{"did":"did:plc:mod","handle":"moderation.example","displayName":"Moderation",
                 "associated":{"labeler":true}},
      "likeCount":999,
      "policies":{
        "labelValues":["!hide","spam","scam","rumor"],
        "labelValueDefinitions":[
          {"identifier":"spam","severity":"inform","blurs":"content","defaultSetting":"hide",
           "adultOnly":false,
           "locales":[{"lang":"en","name":"Spam","description":"Unwanted, repeated actions."},
                      {"lang":"de","name":"Spam","description":"Unerwünschte Wiederholungen."}]},
          {"identifier":"scam","severity":"alert","blurs":"content","defaultSetting":"hide",
           "locales":[{"lang":"en","name":"Scam","description":"Scams, phishing & fraud."}]},
          {"identifier":"rumor","severity":"inform","blurs":"none","defaultSetting":"ignore",
           "locales":[{"lang":"en","name":"Rumour","description":"Unconfirmed claims."}]}
        ]}
    }]}
    """

    private func services() throws -> [LabelerService] {
        struct Response: Decodable { let views: [LabelerService] }
        return try JSONDecoder().decode(Response.self, from: Data(payload.utf8)).views
    }

    @Test("A service decodes with its policies")
    func decoding() throws {
        let service = try #require(services().first)
        #expect(service.did == "did:plc:mod")
        #expect(service.creator.isLabeler)
        #expect(service.policies.labelValues.count == 4)
        #expect(service.definitions.count == 3)
    }

    @Test("A definition is read in the reader's language")
    func localisation() throws {
        let spam = try #require(services().first?.definitions.first { $0.identifier == "spam" })

        L10n.language = .de
        #expect(spam.localisedName == "Spam")
        #expect(spam.localisedDescription == "Unerwünschte Wiederholungen.")

        L10n.language = .en
        #expect(spam.localisedDescription == "Unwanted, repeated actions.")

        // A definition with no German falls back to English rather than to the
        // bare identifier.
        let scam = try #require(services().first?.definitions.first { $0.identifier == "scam" })
        L10n.language = .de
        #expect(scam.localisedName == "Scam")
        L10n.language = .en
    }

    @Test("The published shape becomes a decision the app can act on")
    func toDefinition() throws {
        let definitions = try #require(services().first?.definitions)

        let spam = try #require(definitions.first { $0.identifier == "spam" }).asDefinition
        #expect(spam.blurs == .content)
        #expect(spam.defaultSetting == .hide)
        #expect(spam.adultOnly == false)
        #expect(spam.title == "Spam")

        let scam = try #require(definitions.first { $0.identifier == "scam" }).asDefinition
        #expect(scam.severity == .alert)

        let rumor = try #require(definitions.first { $0.identifier == "rumor" }).asDefinition
        #expect(rumor.defaultSetting == .ignore)
        #expect(rumor.blurs == .none)
    }

    @Test("A labeler's own definition drives the verdict")
    func decidesFromPublishedDefinition() throws {
        let service = try #require(services().first)
        var definitions: [LabelKey: LabelDefinition] = [:]
        for published in service.definitions {
            definitions[LabelKey(labeler: service.did, value: published.identifier)] = published.asDefinition
        }
        var preferences = Preferences()
        preferences.setAdultContent(true)
        let context = ModerationContext(preferences: preferences, definitions: definitions,
                                        viewerDID: "did:plc:me")

        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: nil, avatar: nil,
                                  banner: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil,
                                  verification: nil, labels: nil, associated: nil)
        let post = PostView(uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "c", author: author,
                            record: PostRecord(text: "hi"), embed: nil, replyCount: 0,
                            repostCount: 0, likeCount: 0, indexedAt: "2026-08-29T00:00:00Z",
                            viewer: nil, labels: [ContentLabel(src: service.did, val: "spam", uri: nil)])

        // The service asks for hide by default, so the post goes.
        #expect(Moderation.decide(post: post, context: context).verdict == .hide)

        // The same label from a service nobody subscribed to has no definition,
        // so it can only say something — it cannot act.
        let stranger = PostView(uri: post.uri, cid: "c", author: author, record: post.record,
                                embed: nil, replyCount: 0, repostCount: 0, likeCount: 0,
                                indexedAt: post.indexedAt, viewer: nil,
                                labels: [ContentLabel(src: "did:plc:nobody", val: "spam", uri: nil)])
        #expect(Moderation.decide(post: stranger, context: context).verdict == .badge)
    }

    @Test("A label fetched from the labeler counts once, not twice")
    func mergedLabels() {
        var preferences = Preferences()
        preferences.setAdultContent(true)
        let context = ModerationContext(preferences: preferences, viewerDID: "did:plc:me")

        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: nil, avatar: nil,
                                  banner: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil,
                                  verification: nil, labels: nil, associated: nil)
        let label = ContentLabel(src: "did:plc:l", val: "nudity", uri: nil)
        let post = PostView(uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "c", author: author,
                            record: PostRecord(text: "hi"), embed: nil, replyCount: 0,
                            repostCount: 0, likeCount: 0, indexedAt: "2026-08-29T00:00:00Z",
                            viewer: nil, labels: [label])

        let decision = Moderation.decide(post: post, extraLabels: [label], context: context)
        #expect(decision.labels == ["nudity"])
        #expect(decision.verdict == .blurMedia)
    }

    @Test("A retracted label does not act")
    func negatedLabel() {
        var preferences = Preferences()
        preferences.setAdultContent(true)
        let context = ModerationContext(preferences: preferences, viewerDID: "did:plc:me")

        let author = ActorProfile(did: "did:plc:a", handle: "a.test", displayName: nil, avatar: nil,
                                  banner: nil, description: nil, followersCount: nil,
                                  followsCount: nil, postsCount: nil, viewer: nil,
                                  verification: nil, labels: nil, associated: nil)
        let post = PostView(uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "c", author: author,
                            record: PostRecord(text: "hi"), embed: nil, replyCount: 0,
                            repostCount: 0, likeCount: 0, indexedAt: "2026-08-29T00:00:00Z",
                            viewer: nil,
                            labels: [ContentLabel(src: "did:plc:l", val: "porn", uri: nil, neg: true)])

        #expect(Moderation.decide(post: post, context: context).verdict == .allow)
    }

    @Test("Subscriptions are stored as the protocol writes them")
    func subscriptionPreference() {
        var preferences = Preferences()
        preferences.setSubscribedLabelers(["did:plc:a", "did:plc:b"])
        #expect(preferences.subscribedLabelers == ["did:plc:a", "did:plc:b"])

        preferences.setSubscribedLabelers(["did:plc:b"])
        #expect(preferences.subscribedLabelers == ["did:plc:b"])
        // One entry, not two.
        #expect(preferences.entries.filter { $0.type == Preferences.labelers }.count == 1)
    }
}
