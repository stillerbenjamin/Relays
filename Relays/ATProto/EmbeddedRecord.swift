//
//  EmbeddedRecord.swift
//  Relays
//
//  A post can embed a record, and the protocol allows eight different things to
//  be on the other end of that reference. The app read one of them — a quoted
//  post — and drew the rest as nothing, or worse, as an empty bordered box.
//
//  Three of the eight are not content at all but explanations of why the quote
//  is gone: deleted, blocked, or detached by its author. Drawing those as blank
//  space turns an answer into a gap. The app can even produce the third one
//  itself: it writes postgates, and a postgate is exactly what detaches a quote.
//
//  Shapes for `generatorView`, `starterPackViewBasic` and `viewNotFound` were
//  taken from live replies; the rest from the lexicon.
//

import Foundation

/// The union at `app.bsky.embed.record#view`.
enum EmbeddedRecord: Codable, Hashable {
    case post(QuotedPost)
    case feed(EmbeddedFeed)
    case list(EmbeddedList)
    case starterPack(EmbeddedStarterPack)
    case labeler(EmbeddedLabeler)
    /// The record is gone.
    case notFound
    /// Its author is blocked, or blocks the reader. Only a DID comes back here
    /// — `app.bsky.feed.defs#blockedAuthor` has no handle, which is exactly what
    /// used to make this variant fatal.
    case blocked(did: String?)
    /// The quoted author took the quote back, through a postgate.
    case detached
    /// A ninth thing the protocol has not invented yet.
    case unknown

    /// The quoted post, where there is one. Everything that only wants to know
    /// "is this a quote of a post" goes through here.
    var post: QuotedPost? {
        if case .post(let quoted) = self { return quoted }
        return nil
    }

    /// Where tapping the card should lead, if anywhere.
    var uri: String? {
        switch self {
        case .post(let quoted): return quoted.uri
        case .feed(let feed): return feed.uri
        case .list(let list): return list.uri
        case .starterPack(let pack): return pack.uri
        case .labeler(let labeler): return labeler.uri
        case .notFound, .blocked, .detached, .unknown: return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type", author
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "app.bsky.embed.record#viewRecord", "":
            // An older reply may carry no `$type` at all; a quoted post is what
            // that used to mean.
            self = .post(try QuotedPost(from: decoder))
        case "app.bsky.embed.record#viewNotFound":
            self = .notFound
        case "app.bsky.embed.record#viewBlocked":
            self = .blocked(did: (try? c.decode(BlockedAuthor.self, forKey: .author))?.did)
        case "app.bsky.embed.record#viewDetached":
            self = .detached
        case "app.bsky.feed.defs#generatorView":
            self = .feed(try EmbeddedFeed(from: decoder))
        case "app.bsky.graph.defs#listView":
            self = .list(try EmbeddedList(from: decoder))
        case "app.bsky.graph.defs#starterPackViewBasic":
            self = .starterPack(try EmbeddedStarterPack(from: decoder))
        case "app.bsky.labeler.defs#labelerView":
            self = .labeler(try EmbeddedLabeler(from: decoder))
        default:
            self = .unknown
        }
    }

    /// Written only into the feed cache, and read back by the initialiser above.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .post(let quoted):
            try c.encode("app.bsky.embed.record#viewRecord", forKey: .type)
            try quoted.encode(to: encoder)
        case .feed(let feed):
            try c.encode("app.bsky.feed.defs#generatorView", forKey: .type)
            try feed.encode(to: encoder)
        case .list(let list):
            try c.encode("app.bsky.graph.defs#listView", forKey: .type)
            try list.encode(to: encoder)
        case .starterPack(let pack):
            try c.encode("app.bsky.graph.defs#starterPackViewBasic", forKey: .type)
            try pack.encode(to: encoder)
        case .labeler(let labeler):
            try c.encode("app.bsky.labeler.defs#labelerView", forKey: .type)
            try labeler.encode(to: encoder)
        case .notFound:
            try c.encode("app.bsky.embed.record#viewNotFound", forKey: .type)
        case .blocked(let did):
            try c.encode("app.bsky.embed.record#viewBlocked", forKey: .type)
            try c.encodeIfPresent(did.map(BlockedAuthor.init(did:)), forKey: .author)
        case .detached:
            try c.encode("app.bsky.embed.record#viewDetached", forKey: .type)
        case .unknown:
            break
        }
    }
}

// MARK: - The four that are content

struct EmbeddedFeed: Codable, Hashable {
    var uri: String?
    var displayName: String?
    var description: String?
    var avatar: String?
    var likeCount: Int?
    var creator: ActorProfile?

    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
}

struct EmbeddedList: Codable, Hashable {
    var uri: String?
    var name: String?
    var description: String?
    var avatar: String?
    var purpose: String?
    var listItemCount: Int?
    var creator: ActorProfile?

    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
}

/// The basic view carries no name of its own — it is in the record it points at.
struct EmbeddedStarterPack: Codable, Hashable {
    var uri: String?
    var joinedAllTimeCount: Int?
    var listItemCount: Int?
    var creator: ActorProfile?
    var record: Record?

    struct Record: Codable, Hashable {
        var name: String?
        var description: String?
    }

    var name: String? { record?.name }
}

/// `app.bsky.feed.defs#blockedAuthor` — a DID and a viewer state, and no handle.
/// Reading it as a full profile is what threw.
struct BlockedAuthor: Codable, Hashable {
    let did: String
}

/// A labeler view names nobody either; the service is its creator.
struct EmbeddedLabeler: Codable, Hashable {
    var uri: String?
    var likeCount: Int?
    var creator: ActorProfile?
}
