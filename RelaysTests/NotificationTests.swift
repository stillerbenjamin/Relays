//
//  NotificationTests.swift
//  RelaysTests
//
//  The notification path had three silent total failures in it. None of them
//  raised an error, none was visible in a screenshot, and none was covered.
//

import Testing
import Foundation
@testable import Relays

@Suite("Notification reasons")
struct NotificationReasonTests {

    private func notification(_ reason: String, pack: String? = nil) -> ATNotification {
        ATNotification(
            uri: "at://did:plc:a/app.bsky.feed.like/1", cid: "bafy",
            author: ActorProfile(did: "did:plc:a", handle: "ada.example.com",
                                 displayName: "Ada", avatar: nil, banner: nil,
                                 description: nil, followersCount: nil, followsCount: nil,
                                 postsCount: nil, viewer: nil),
            reason: reason, reasonSubject: "at://did:plc:me/app.bsky.feed.post/9",
            isRead: false, indexedAt: "2026-09-03T10:00:00Z", record: nil,
            starterPack: pack.map { .init(uri: "at://pack", record: .init(name: $0)) },
            labels: nil)
    }

    /// The protocol names thirteen. The app knew six, and the other seven were
    /// shown to the reader as the raw lexicon token — a banner reading
    /// "Ada starterpack-joined", in both languages.
    @Test("Every reason the protocol names has words", arguments: ATNotification.Reason.allCases)
    func everyReasonSpeaks(_ reason: ATNotification.Reason) {
        let item = notification(reason.rawValue)
        #expect(item.known == reason)
        #expect(!item.verb.isEmpty)
        // The tell-tale: a raw token contains a hyphen or is the wire string.
        #expect(item.verb != reason.rawValue)
        #expect(!item.symbol.isEmpty)
    }

    @Test("There are thirteen of them, and the wire strings are the wire strings")
    func theThirteen() {
        #expect(ATNotification.Reason.allCases.count == 13)
        let wire = Set(ATNotification.Reason.allCases.map(\.rawValue))
        #expect(wire.contains("starterpack-joined"))
        #expect(wire.contains("like-via-repost"))
        #expect(wire.contains("repost-via-repost"))
        #expect(wire.contains("subscribed-post"))
        #expect(wire.contains("contact-match"))
    }

    /// A fourteenth is a matter of time; the lexicon calls these known values,
    /// not a closed set.
    @Test("A reason from the future says something honest, not its own name")
    func fourteenth() {
        let item = notification("something-new")
        #expect(item.known == nil)
        #expect(item.verb != "something-new")
        #expect(item.verb == L10n.t(.verbUnknown))
        #expect(item.symbol == "bell")
    }

    /// The field is decoded for exactly this.
    @Test("A starter pack notification names the pack when the server sent one")
    func starterPackName() {
        #expect(notification("starterpack-joined", pack: "Astronomers").verb.contains("Astronomers"))
        #expect(notification("starterpack-joined").verb == L10n.t(.verbStarterpackJoined))
    }

    /// A reply's subject is *your* post; the reply itself is the notification's
    /// own uri. Tapping "replied" used to open what was replied to.
    @Test("A notification leads to the thing worth reading")
    func whereItLeads() {
        let reply = ATNotification(
            uri: "at://did:plc:a/app.bsky.feed.post/theReply", cid: "bafy",
            author: notification("reply").author, reason: "reply",
            reasonSubject: "at://did:plc:me/app.bsky.feed.post/mine",
            isRead: false, indexedAt: "2026-09-03T10:00:00Z", record: nil,
            starterPack: nil, labels: nil)
        #expect(reply.postToOpen == "at://did:plc:a/app.bsky.feed.post/theReply")

        // A like is about your post, so that is where it goes.
        #expect(notification("like").postToOpen == "at://did:plc:me/app.bsky.feed.post/9")
        // A follow is about a person; there is no post.
        #expect(notification("follow").postToOpen == nil)
        #expect(notification("verified").postToOpen == nil)
    }

    @Test("Two notifications on one record are two notifications")
    func identity() {
        #expect(notification("like").id != notification("repost").id)
        #expect(notification("like").id.contains("|"))
    }
}

@MainActor
@Suite("Notification delivery, per account", .serialized)
struct NotificationAccountTests {

    private func item(_ minutesAgo: Int) -> ATNotification {
        let stamp = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
        return ATNotification(
            uri: "at://did:plc:a/app.bsky.feed.like/\(minutesAgo)", cid: "bafy",
            author: ActorProfile(did: "did:plc:a", handle: "ada.example.com",
                                 displayName: nil, avatar: nil, banner: nil, description: nil,
                                 followersCount: nil, followsCount: nil, postsCount: nil,
                                 viewer: nil),
            reason: "like", reasonSubject: nil, isRead: false, indexedAt: stamp,
            record: nil, starterPack: nil, labels: nil)
    }

    private struct Kinds: NotificationKinds {
        func wantsNotification(ofKind reason: String) -> Bool { true }
    }

    /// The watermark used to be one device-wide key. Switching to an account
    /// whose notifications were older than the first account's watermark
    /// delivered nothing — ever, on that device, with nothing to notice.
    @Test("Each account has its own watermark")
    func perAccount() {
        let service = NotificationService()

        service.use(account: "did:plc:first")
        service.catchUp()                       // first account is caught up to now

        service.use(account: "did:plc:second")
        // A fresh account starts at now too, but from its own key — and an hour
        // -old notification is not delivered to either.
        let old = [item(60)]
        #expect(NotificationService.selecting(from: old, settings: Kinds(),
                                              since: Date().addingTimeInterval(-1)).isEmpty)

        // Coming back finds the first account's mark, not the second's.
        service.use(account: "did:plc:first")
        #expect(service.account == "did:plc:first")
    }

    /// While notifications were off the watermark stood still, so switching them
    /// on delivered everything since — up to twenty-five banners in one loop.
    @Test("A backlog becomes a handful and a line, not twenty-five banners")
    func burst() {
        let many = (1...20).map { item($0) }
        let picked = NotificationService.selecting(from: many, settings: Kinds(),
                                                   since: Date().addingTimeInterval(-3600))
        #expect(picked.count == 20)
        #expect(picked.count > NotificationService.burstLimit)
        // Five is what gets a banner; the rest is one summary.
        #expect(NotificationService.burstLimit == 5)
    }
}

@MainActor
@Suite("Notification preferences")
struct NotificationPreferenceTests {

    /// Eight kinds carry an audience, four do not. Sending an `include` on one
    /// of the four — or omitting it on one of the eight — is a lexicon
    /// validation failure, and it is the easiest thing here to get wrong.
    @Test("The audience goes only on the kinds that have one")
    func filterableSplit() throws {
        let data = try JSONEncoder().encode(NotificationPreferences.defaults)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json.count == 12)
        for kind in NotificationPreferences.Kind.allCases {
            let entry = try #require(json[kind.rawValue] as? [String: Any],
                                     "\(kind.rawValue) is missing from the body")
            #expect(entry["list"] != nil)
            #expect(entry["push"] != nil)
            if kind.isFilterable {
                #expect(entry["include"] != nil, "\(kind.rawValue) needs an audience")
            } else {
                #expect(entry["include"] == nil, "\(kind.rawValue) must not carry an audience")
            }
        }
        // The split itself, spelled out.
        #expect(NotificationPreferences.Kind.allCases.filter(\.isFilterable).count == 8)
    }

    /// `chat` is a preference with no notification reason; `contact-match` is a
    /// reason with no preference. One type for both would produce a setting for
    /// something that never arrives, or an arrival with no setting.
    @Test("The two sets overlap, and neither contains the other")
    func twoSets() {
        #expect(NotificationPreferences.Kind.governing(.contactMatch) == nil)
        for reason in ATNotification.Reason.allCases where reason != .contactMatch {
            #expect(NotificationPreferences.Kind.governing(reason) != nil,
                    "\(reason.rawValue) has no preference")
        }
        // And nothing in the app models `chat` here; that is chat.bsky's.
        #expect(!NotificationPreferences.Kind.allCases.map(\.rawValue).contains("chat"))
    }

    @Test("What the server sends comes back the same")
    func roundTrip() throws {
        var prefs = NotificationPreferences.defaults
        prefs[.like] = .init(include: .follows, list: true, push: false)
        prefs[.verified] = .init(include: nil, list: false, push: false)

        let back = try JSONDecoder().decode(NotificationPreferences.self,
                                            from: try JSONEncoder().encode(prefs))
        #expect(back[.like].include == .follows)
        #expect(back[.like].push == false)
        #expect(back[.verified].list == false)
        #expect(back[.verified].include == nil)
    }

    /// A server that sends a shape the lexicon forbids must not make the app
    /// send one back.
    @Test("A malformed answer is straightened out rather than echoed")
    func straightensTheWire() throws {
        let json = Data(#"""
        {"like":{"list":true,"push":true},
         "verified":{"include":"follows","list":true,"push":true}}
        """#.utf8)
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: json)
        // `like` is filterable and arrived without one: filled in.
        #expect(prefs[.like].include == .all)
        // `verified` is not, and arrived with one: dropped.
        #expect(prefs[.verified].include == nil)
    }

    @Test("The delivery rule now comes from the account")
    func deliveryRule() {
        var prefs = NotificationPreferences.defaults
        prefs[.like].push = false
        #expect(!prefs.wantsNotification(ofKind: "like"))
        #expect(prefs.wantsNotification(ofKind: "repost"))

        // Replies, mentions and quotes used to share one switch. They do not.
        prefs[.reply].push = false
        #expect(!prefs.wantsNotification(ofKind: "reply"))
        #expect(prefs.wantsNotification(ofKind: "mention"))
        #expect(prefs.wantsNotification(ofKind: "quote"))

        // No preference to consult: let it through rather than swallow it.
        #expect(prefs.wantsNotification(ofKind: "contact-match"))
        #expect(prefs.wantsNotification(ofKind: "something-new"))
    }

    @Test("A mixed audience is reported as mixed, not as a guess")
    func mixedAudience() {
        var prefs = NotificationPreferences.defaults
        #expect(prefs.sharedAudience == .all)
        prefs[.like].include = .follows
        #expect(prefs.sharedAudience == nil)
        prefs.setAudience(.follows)
        #expect(prefs.sharedAudience == .follows)
        // Setting the audience touches only the eight that have one.
        #expect(prefs[.verified].include == nil)
    }
}
