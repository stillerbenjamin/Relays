//
//  ThreadFixture.swift
//  RelaysTests
//
//  One conversation, six accounts, people answering each other rather than a
//  list of unrelated posts. A thread is the screen where the app has to show
//  who is talking to whom, and until now nothing in the project had ever put a
//  real one in front of a renderer.
//
//  Shared by the iOS and macOS snapshots so both platforms draw the same
//  conversation and can be compared side by side.
//

import Foundation
@testable import Relays

enum ThreadFixture {

    // MARK: - The people

    /// Runs her own server. The thread starts with her.
    static let anna = person("anna.pds.example.com", "Anna Weiß",
                             "Baut an dezentralen Netzen. Eigener PDS seit 2026.",
                             followers: 1_284)

    /// Works on the protocol.
    static let jay = person("jay.bsky.team", "Jay",
                            "Protokoll, nicht Plattform.", followers: 92_400)

    /// Writes the tooling everybody ends up using.
    static let maria = person("maria.dev", "Maria Lindqvist",
                              "Firehose-Werkzeuge. Schwedisch, Deutsch, Go.",
                              followers: 8_130)

    /// Sceptical, and usually right about the awkward part.
    static let tomas = person("tomas.ruiz.dev", "Tomás Ruiz",
                              "Betreibt Server, seit das noch niemand wollte.",
                              followers: 3_402)

    /// Asks the question everybody else was too polite to ask.
    static let nadia = person("nadia.okonkwo.net", "Nadia Okonkwo",
                              "Netzwerkforschung. Lagos → Berlin.", followers: 15_700)

    /// New here, and the reason the thread stays readable.
    static let alex = person("alex.bsky.social", "Alex",
                             "Gerade erst angekommen.", followers: 61)

    static let everyone = [anna, jay, maria, tomas, nadia, alex]

    // MARK: - The conversation

    /// What sits above the post being read: Anna's opening line, then Jay's
    /// answer to it.
    static let ancestors: [PostView] = [
        post(anna, "Migration auf den eigenen PDS ist durch. Elf Minuten, "
             + "keine verlorenen Posts, dieselbe Identität. Das DID-Dokument "
             + "zeigt jetzt auf meinen Server.",
             minutesAgo: 214, replies: 23, reposts: 41, likes: 318, quotes: 6),

        post(jay, "Genau dafür ist die DID da. Der Server ist eine Adresse, "
             + "kein Besitzverhältnis — du hättest auch dreimal umziehen können.",
             minutesAgo: 198, replies: 9, reposts: 12, likes: 204)
    ]

    /// The post the reader opened. Maria answering Jay.
    static let focused = post(maria,
        "Der ehrliche Teil: elf Minuten, weil Anna 2 100 Posts hat. Bei "
        + "200 000 sieht die CAR-Datei anders aus. Ich messe das gerade.",
        minutesAgo: 176, replies: 4, reposts: 8, likes: 96, quotes: 2, liked: true)

    /// The replies to it — four accounts, three of them answering each other
    /// rather than the post above.
    static let replies: [PostView] = [
        post(tomas, "Genau die Zahl fehlt überall. Ein Umzug, den niemand "
             + "misst, ist ein Versprechen, keine Funktion.",
             minutesAgo: 171, replies: 2, reposts: 3, likes: 61),

        post(nadia, "@tomas.ruiz.dev Und die Latenz zum Relay danach? Ein "
             + "eigener Server in Lagos ist etwas anderes als einer in Virginia.",
             minutesAgo: 164, replies: 1, reposts: 6, likes: 88,
             mentioning: [tomas]),

        post(maria, "@nadia.okonkwo.net Steht auf derselben Liste. Ich lasse "
             + "beide Messungen zusammen laufen und poste die Rohdaten.",
             minutesAgo: 158, replies: 0, reposts: 2, likes: 47, reposted: true,
             mentioning: [nadia]),

        post(alex, "Ich lese hier seit einer Woche mit und verstehe zum ersten "
             + "Mal, warum das nicht dasselbe ist wie ein Konto woanders. Danke.",
             minutesAgo: 96, replies: 0, reposts: 0, likes: 12),

        post(anna, "Rohdaten kriegst du von mir auch — mein Repo ist als CAR "
             + "exportierbar, das ist ja der Punkt.",
             minutesAgo: 44, replies: 0, reposts: 1, likes: 29)
    ]

    /// The whole conversation in reading order.
    static var everything: [PostView] { ancestors + [focused] + replies }

    // MARK: - Builders

    private static func person(_ handle: String, _ name: String,
                               _ bio: String, followers: Int) -> ActorProfile {
        ActorProfile(did: "did:plc:\(handle.prefix(8).filter(\.isLetter))",
                     handle: handle, displayName: name, avatar: nil, banner: nil,
                     description: bio, followersCount: followers,
                     followsCount: nil, postsCount: nil, viewer: nil)
    }

    /// A mention is only an interaction if it is a facet. The protocol indexes
    /// facets in UTF-8 bytes, not characters, so the offsets are counted on the
    /// encoded text — the fixture would be wrong the first time somebody put an
    /// accent before a handle, and Tomás has one.
    private static func mentions(_ who: [ActorProfile], in text: String) -> [Facet]? {
        let bytes = Array(text.utf8)
        let facets: [Facet] = who.compactMap { person in
            let needle = Array("@\(person.handle)".utf8)
            guard let start = firstRange(of: needle, in: bytes) else { return nil }
            return Facet(index: .init(byteStart: start, byteEnd: start + needle.count),
                         features: [.mention(did: person.did)])
        }
        return facets.isEmpty ? nil : facets
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }

    private static func post(_ author: ActorProfile, _ text: String,
                             minutesAgo: Int, replies: Int, reposts: Int,
                             likes: Int, quotes: Int = 0,
                             liked: Bool = false, reposted: Bool = false,
                             mentioning: [ActorProfile] = []) -> PostView {
        let created = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
        return PostView(
            uri: "at://\(author.did)/app.bsky.feed.post/\(abs(text.hashValue) % 100_000)",
            cid: "bafy", author: author,
            record: PostRecord(text: text, createdAt: created,
                               facets: mentions(mentioning, in: text)),
            embed: nil, replyCount: replies, repostCount: reposts, likeCount: likes,
            quoteCount: quotes > 0 ? quotes : nil, indexedAt: created,
            viewer: (liked || reposted)
                ? PostViewerState(like: liked ? "at://like" : nil,
                                  repost: reposted ? "at://repost" : nil)
                : nil,
            labels: nil)
    }
}
