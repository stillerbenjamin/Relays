//
//  ATProtoModels.swift
//  Relays
//
//  Lexicon models for the com.atproto.* and app.bsky.* endpoints in use.
//

import Foundation

// MARK: - Session

struct ATSession: Codable, Equatable {
    var accessJwt: String
    var refreshJwt: String
    var handle: String
    var did: String
    var email: String?
    /// Host of the PDS the session was created against.
    var service: String = ATProtoClient.defaultService

    enum CodingKeys: String, CodingKey {
        case accessJwt, refreshJwt, handle, did, email
    }

    init(accessJwt: String, refreshJwt: String, handle: String, did: String, email: String?, service: String) {
        self.accessJwt = accessJwt
        self.refreshJwt = refreshJwt
        self.handle = handle
        self.did = did
        self.email = email
        self.service = service
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessJwt = try c.decode(String.self, forKey: .accessJwt)
        refreshJwt = try c.decode(String.self, forKey: .refreshJwt)
        handle = try c.decode(String.self, forKey: .handle)
        did = try c.decode(String.self, forKey: .did)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        service = ATProtoClient.defaultService
    }
}

/// Session as stored in the keychain, including its service host.
/// A DPoP key means the session came from OAuth and must be renewed that way.
struct StoredSession: Codable, Equatable {
    var session: ATSession
    var service: String
    var dpopKey: Data?

    var isOAuth: Bool { dpopKey != nil }
}

// MARK: - Actor

struct ActorProfile: Codable, Identifiable, Hashable {
    let did: String
    let handle: String
    var displayName: String?
    var avatar: String?
    var banner: String?
    var description: String?
    var followersCount: Int?
    var followsCount: Int?
    var postsCount: Int?
    var viewer: ActorViewerState?
    var verification: VerificationState?
    var labels: [ContentLabel]?
    var associated: AssociatedState?

    var id: String { did }
    /// Accounts that also run a moderation service can be subscribed to.
    var isLabeler: Bool { associated?.labeler == true }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var bannerURL: URL? { banner.flatMap(URL.init(string:)) }
    var name: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? handle : trimmed
    }
}

/// Verification as the network states it. Two distinct things: an account that
/// was verified, and one that is trusted to verify others.
struct VerificationState: Codable, Hashable {
    var verifiedStatus: String?
    var trustedVerifierStatus: String?

    var isVerified: Bool { verifiedStatus == "valid" }
    var isTrustedVerifier: Bool { trustedVerifierStatus == "valid" }
}

/// What an account runs besides posting.
struct AssociatedState: Codable, Hashable {
    var labeler: Bool?
    var lists: Int?
    var feedgens: Int?
}

struct ActorViewerState: Codable, Hashable {
    var following: String?
    var followedBy: String?
    var muted: Bool?
    var blocking: String?
    /// The other side blocked this account. Nothing can be undone from here.
    var blockedBy: Bool?
    /// Muted or blocked because a subscribed list carries this account, rather
    /// than by a decision about them alone.
    var mutedByList: ListRef?
    var blockingByList: ListRef?
}

/// Just the part of a list view that a viewer state needs.
struct ListRef: Codable, Hashable {
    let uri: String
    var name: String?
}

// MARK: - Feed

struct FeedResponse: Codable {
    let feed: [FeedViewPost]
    let cursor: String?

    init(feed: [FeedViewPost], cursor: String?) {
        self.feed = feed
        self.cursor = cursor
    }
}

struct FeedViewPost: Codable, Identifiable, Hashable {
    let post: PostView
    var reply: ReplyRef?
    var reason: Reason?

    init(post: PostView, reply: ReplyRef? = nil, reason: Reason? = nil) {
        self.post = post
        self.reply = reply
        self.reason = reason
    }

    /// The account that put this post in front of the reader, when that is not
    /// the account that wrote it. Every list has to say so, or a repost reads
    /// as the reposter's own words.
    var repostedBy: ActorProfile? {
        if case .repost(let by, _)? = reason { return by }
        return nil
    }

    /// Stays unique when the same post reappears as a repost.
    var id: String {
        if case .repost(let by, let at)? = reason {
            return "\(post.uri)|repost|\(by.did)|\(at)"
        }
        return post.uri
    }

    struct ReplyRef: Codable, Hashable {
        var root: PostView?
        var parent: PostView?
    }

    enum Reason: Codable, Hashable {
        case repost(by: ActorProfile, indexedAt: String)
        case other

        private enum CodingKeys: String, CodingKey {
            case type = "$type", by, indexedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
            if type == "app.bsky.feed.defs#reasonRepost",
               let by = try c.decodeIfPresent(ActorProfile.self, forKey: .by) {
                self = .repost(by: by, indexedAt: try c.decodeIfPresent(String.self, forKey: .indexedAt) ?? "")
            } else {
                self = .other
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if case .repost(let by, let indexedAt) = self {
                try c.encode("app.bsky.feed.defs#reasonRepost", forKey: .type)
                try c.encode(by, forKey: .by)
                try c.encode(indexedAt, forKey: .indexedAt)
            }
        }
    }
}

struct PostView: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let author: ActorProfile
    let record: PostRecord
    var embed: PostEmbed?
    var replyCount: Int?
    var repostCount: Int?
    var likeCount: Int?
    /// How often this post has been quoted. Sent with every post, and the only
    /// sign a quote leaves on the post it points at.
    var quoteCount: Int?
    var indexedAt: String
    var viewer: PostViewerState?
    var labels: [ContentLabel]?

    var id: String { uri }

    /// The rkey — last path component of the AT URI.
    var rkey: String { uri.split(separator: "/").last.map(String.init) ?? "" }
}

/// A moderation label applied by a labeler service.
struct ContentLabel: Codable, Hashable, Identifiable {
    let src: String
    let val: String
    var uri: String?
    /// A labeler takes a label back by issuing it again, negated.
    var neg: Bool?

    var id: String { src + val }
    var isNegated: Bool { neg == true }
}

struct PostViewerState: Codable, Hashable {
    var like: String?
    var repost: String?
    /// The author's rules do not let this reader answer.
    var replyDisabled: Bool?
    /// The author does not allow quotes of this post.
    var embeddingDisabled: Bool?
}

struct PostRecord: Codable, Hashable {
    var text: String
    var createdAt: String?
    var facets: [Facet]?
    var reply: ReplyRefStrong?

    struct ReplyRefStrong: Codable, Hashable {
        var root: StrongRef
        var parent: StrongRef
    }

    init(text: String, createdAt: String? = nil, facets: [Facet]? = nil, reply: ReplyRefStrong? = nil) {
        self.text = text
        self.createdAt = createdAt
        self.facets = facets
        self.reply = reply
    }

    /// Records from other collections (likes in notifications) carry no `text`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        facets = try? c.decode([Facet].self, forKey: .facets)
        reply = try? c.decode(ReplyRefStrong.self, forKey: .reply)
    }
}

struct StrongRef: Codable, Hashable {
    let uri: String
    let cid: String
}

// MARK: - Facets (Rich Text)

struct Facet: Codable, Hashable {
    var index: ByteSlice
    var features: [Feature]

    struct ByteSlice: Codable, Hashable {
        var byteStart: Int
        var byteEnd: Int
    }

    enum Feature: Codable, Hashable {
        case link(uri: String)
        case mention(did: String)
        case tag(String)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case type = "$type", uri, did, tag
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decodeIfPresent(String.self, forKey: .type) ?? "" {
            case "app.bsky.richtext.facet#link":
                self = .link(uri: try c.decode(String.self, forKey: .uri))
            case "app.bsky.richtext.facet#mention":
                self = .mention(did: try c.decode(String.self, forKey: .did))
            case "app.bsky.richtext.facet#tag":
                self = .tag(try c.decode(String.self, forKey: .tag))
            default:
                self = .unknown
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .link(let uri):
                try c.encode("app.bsky.richtext.facet#link", forKey: .type)
                try c.encode(uri, forKey: .uri)
            case .mention(let did):
                try c.encode("app.bsky.richtext.facet#mention", forKey: .type)
                try c.encode(did, forKey: .did)
            case .tag(let tag):
                try c.encode("app.bsky.richtext.facet#tag", forKey: .type)
                try c.encode(tag, forKey: .tag)
            case .unknown:
                break
            }
        }
    }
}

// MARK: - Embeds

indirect enum PostEmbed: Codable, Hashable {
    case images([EmbedImage])
    case video(EmbedVideo)
    case external(EmbedExternal)
    /// Not always a quoted post — see `EmbeddedRecord` for the other seven
    /// things the protocol allows on the other end of the reference.
    case record(EmbeddedRecord?)
    /// A quote that also carries media. Both halves are kept — showing only the
    /// picture is what made a quote disappear from the post that made it.
    case recordWithMedia(media: PostEmbed, record: EmbeddedRecord?)
    case unsupported

    private enum CodingKeys: String, CodingKey {
        case type = "$type", images, external, record, media
        case cid, playlist, thumbnail, alt, aspectRatio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "app.bsky.embed.images#view":
            self = .images(try c.decode([EmbedImage].self, forKey: .images))
        case "app.bsky.embed.video#view":
            // Video views carry their fields on the embed itself, not in a nested object.
            self = .video(EmbedVideo(
                cid: try? c.decode(String.self, forKey: .cid),
                playlist: try? c.decode(String.self, forKey: .playlist),
                thumbnail: try? c.decode(String.self, forKey: .thumbnail),
                alt: try? c.decode(String.self, forKey: .alt),
                aspectRatio: try? c.decode(EmbedImage.AspectRatio.self, forKey: .aspectRatio)))
        case "app.bsky.embed.external#view":
            self = .external(try c.decode(EmbedExternal.self, forKey: .external))
        case "app.bsky.embed.record#view":
            self = .record(try c.decodeIfPresent(EmbeddedRecord.self, forKey: .record))
        case "app.bsky.embed.recordWithMedia#view":
            // The quoted post sits one level deeper here than in a plain quote:
            // `record.record` rather than `record`.
            let quoted = (try? c.decode(NestedRecord.self, forKey: .record))?.record

            var media = PostEmbed.unsupported
            if let container = try? c.decode(MediaContainer.self, forKey: .media) {
                if let images = container.images {
                    media = .images(images)
                } else if let playlist = container.playlist {
                    media = .video(EmbedVideo(cid: container.cid, playlist: playlist,
                                              thumbnail: container.thumbnail, alt: container.alt,
                                              aspectRatio: container.aspectRatio))
                }
            }
            self = .recordWithMedia(media: media, record: quoted)
        default:
            self = .unsupported
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .images(let images):
            try c.encode("app.bsky.embed.images#view", forKey: .type)
            try c.encode(images, forKey: .images)
        case .video(let video):
            try c.encode("app.bsky.embed.video#view", forKey: .type)
            try c.encodeIfPresent(video.cid, forKey: .cid)
            try c.encodeIfPresent(video.playlist, forKey: .playlist)
            try c.encodeIfPresent(video.thumbnail, forKey: .thumbnail)
            try c.encodeIfPresent(video.alt, forKey: .alt)
        case .external(let external):
            try c.encode("app.bsky.embed.external#view", forKey: .type)
            try c.encode(external, forKey: .external)
        case .record(let record):
            try c.encode("app.bsky.embed.record#view", forKey: .type)
            try c.encodeIfPresent(record, forKey: .record)
        case .recordWithMedia(let media, let record):
            // Written only into the feed cache, which reads it back through the
            // same nesting the network uses.
            try c.encode("app.bsky.embed.recordWithMedia#view", forKey: .type)
            try c.encode(Nested(record: record), forKey: .record)
            try c.encode(media, forKey: .media)
        case .unsupported:
            break
        }
    }

    /// False for shapes the app draws nothing for — the caller then skips the
    /// spacing around the embed as well.
    var isRenderable: Bool {
        switch self {
        case .unsupported: return false
        // Every variant of an embedded record draws something now, including
        // the three that only explain why the quote is gone.
        case .record(let record): return record != nil
        case .recordWithMedia(let media, let record):
            return record != nil || media.isRenderable
        default: return true
        }
    }

    /// The post this one quotes, wherever it is carried.
    var quoted: QuotedPost? {
        switch self {
        case .record(let record): return record?.post
        case .recordWithMedia(_, let record): return record?.post
        default: return nil
        }
    }

    /// `recordWithMedia` wraps the quoted post in one more object than a plain
    /// quote does.
    private struct NestedRecord: Decodable {
        let record: EmbeddedRecord?
    }

    private struct Nested: Encodable {
        let record: EmbeddedRecord?
    }

    private struct MediaContainer: Codable {
        var images: [EmbedImage]?
        var cid: String?
        var playlist: String?
        var thumbnail: String?
        var alt: String?
        var aspectRatio: EmbedImage.AspectRatio?
    }
}

/// A video attachment. The playlist is an HLS manifest AVPlayer can take directly.
struct EmbedVideo: Codable, Hashable {
    var cid: String?
    var playlist: String?
    var thumbnail: String?
    var alt: String?
    var aspectRatio: EmbedImage.AspectRatio?

    var playlistURL: URL? { playlist.flatMap(URL.init(string:)) }
    var thumbnailURL: URL? { thumbnail.flatMap(URL.init(string:)) }
}

struct EmbedImage: Codable, Hashable, Identifiable {
    var thumb: String?
    var fullsize: String?
    var alt: String?
    var aspectRatio: AspectRatio?

    var id: String { fullsize ?? thumb ?? UUID().uuidString }
    var thumbURL: URL? { thumb.flatMap(URL.init(string:)) }
    var fullsizeURL: URL? { fullsize.flatMap(URL.init(string:)) }

    struct AspectRatio: Codable, Hashable {
        var width: Int
        var height: Int
    }
}

struct EmbedExternal: Codable, Hashable {
    var uri: String
    var title: String?
    var description: String?
    var thumb: String?

    var url: URL? { URL(string: uri) }
    var host: String { URL(string: uri)?.host()?.replacingOccurrences(of: "www.", with: "") ?? uri }
}

/// Zitierter Post innerhalb eines record-Embeds.
struct QuotedPost: Codable, Hashable {
    var uri: String?
    var author: ActorProfile?
    var value: PostRecord?
}

// MARK: - Servers

/// What a server says about itself, unauthenticated.
struct ServerDescription: Decodable, Equatable {
    var did: String?
    var inviteCodeRequired: Bool?
    var phoneVerificationRequired: Bool?
    // Optional, not defaulted: a default value does not make a key optional to
    // the synthesised decoder, and a server that leaves it out would take the
    // whole description down with it.
    var availableUserDomains: [String]?
    var links: Links?

    struct Links: Decodable, Equatable {
        var privacyPolicy: String?
        var termsOfService: String?
    }

    var needsInviteCode: Bool { inviteCodeRequired == true }
    var needsPhone: Bool { phoneVerificationRequired == true }

    /// The suffix a new handle gets here — ".bsky.social" and the like.
    var handleSuffix: String { availableUserDomains?.first ?? "" }

    var privacyPolicyURL: URL? { links?.privacyPolicy.flatMap(URL.init(string:)) }
    var termsURL: URL? { links?.termsOfService.flatMap(URL.init(string:)) }

    /// Bluesky's own host, as the form starts out.
    static let defaultHost = "bsky.social"
}

// MARK: - Thread

struct ThreadResponse: Codable {
    let thread: ThreadNode
}

struct ThreadNode: Codable {
    var post: PostView?
    var parent: Box<ThreadNode>?
    var replies: [ThreadNode]?

    /// Indirection for the recursive type.
    final class Box<T: Codable>: Codable {
        let value: T
        init(_ value: T) { self.value = value }
        init(from decoder: Decoder) throws { value = try T(from: decoder) }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    /// Chain of parent posts, oldest first.
    var ancestors: [PostView] {
        var chain: [PostView] = []
        var node = parent?.value
        while let current = node {
            if let post = current.post { chain.append(post) }
            node = current.parent?.value
        }
        return chain.reversed()
    }
}

// MARK: - Notifications

struct NotificationsResponse: Codable {
    let notifications: [ATNotification]
    let cursor: String?
}

struct ATNotification: Codable, Identifiable, Hashable {
    let uri: String
    let cid: String
    let author: ActorProfile
    /// One of `Reason`'s thirteen, or something the protocol has added since.
    /// Kept as a String on purpose: the lexicon calls these known values, not a
    /// closed set, and a fourteenth must not fail to decode.
    let reason: String
    var reasonSubject: String?
    var isRead: Bool
    var indexedAt: String
    var record: PostRecord?
    /// Present on `starterpack-joined`, and on nothing else.
    var starterPack: StarterPack?
    /// Carried so the shape round-trips, and read by `ContentLabel` consumers if
    /// a notification ever needs moderating. Nothing draws them today, and that
    /// is a decision rather than an oversight: a notification is about somebody
    /// the reader already has a relationship with, and the post behind it is
    /// moderated where it is shown.
    var labels: [ContentLabel]?

    /// The name of the pack somebody joined through, where the server sent one.
    struct StarterPack: Codable, Hashable {
        var uri: String?
        var record: Record?

        struct Record: Codable, Hashable {
            var name: String?
        }

        var name: String? { record?.name }
    }

    /// Concatenation with a separator: `uri` can end in anything, and two
    /// notifications whose uri+reason ran together would share an identity.
    var id: String { uri + "|" + reason }

    /// What the protocol names today. The app reads `reason` as a String and
    /// only uses this to answer questions about it, so a value from the future
    /// costs nothing.
    enum Reason: String, CaseIterable {
        case like, repost, follow, mention, reply, quote
        case starterpackJoined = "starterpack-joined"
        case verified, unverified
        case likeViaRepost = "like-via-repost"
        case repostViaRepost = "repost-via-repost"
        case subscribedPost = "subscribed-post"
        case contactMatch = "contact-match"
    }

    var known: Reason? { Reason(rawValue: reason) }

    /// Which post this notification is about — and it is not always the one the
    /// subject names. A reply's subject is *your* post; the reply itself is the
    /// notification's own uri, and that is what somebody tapping "replied"
    /// wants to read.
    var postToOpen: String? {
        switch known {
        case .reply, .mention, .quote, .subscribedPost:
            return uri.contains("app.bsky.feed.post") ? uri : reasonSubject
        case .like, .repost, .likeViaRepost, .repostViaRepost:
            return reasonSubject
        case .follow, .verified, .unverified, .starterpackJoined, .contactMatch, .none:
            return nil
        }
    }

    /// Never the raw token. A reason the app has not met still gets a sentence
    /// somebody can read — `starterpack-joined` used to appear on screen exactly
    /// like that, in both languages.
    var verb: String {
        switch known {
        case .like: return L10n.t(.verbLike)
        case .repost: return L10n.t(.verbRepost)
        case .follow: return L10n.t(.verbFollow)
        case .mention: return L10n.t(.verbMention)
        case .reply: return L10n.t(.verbReply)
        case .quote: return L10n.t(.verbQuote)
        case .likeViaRepost: return L10n.t(.verbLikeViaRepost)
        case .repostViaRepost: return L10n.t(.verbRepostViaRepost)
        case .starterpackJoined:
            // The server sends the pack's name; saying which one is the whole
            // reason the field is decoded.
            if let name = starterPack?.name, !name.isEmpty {
                return L10n.t(.verbStarterpackNamed, name)
            }
            return L10n.t(.verbStarterpackJoined)
        case .verified: return L10n.t(.verbVerified)
        case .unverified: return L10n.t(.verbUnverified)
        case .subscribedPost: return L10n.t(.verbSubscribedPost)
        case .contactMatch: return L10n.t(.verbContactMatch)
        case .none: return L10n.t(.verbUnknown)
        }
    }

    var symbol: String {
        switch known {
        case .like, .likeViaRepost: return "heart.fill"
        case .repost, .repostViaRepost: return "arrow.2.squarepath"
        case .follow: return "person.fill"
        case .contactMatch: return "person.crop.circle.badge.plus"
        case .mention, .reply, .quote, .subscribedPost: return "text.bubble"
        case .starterpackJoined: return "person.badge.plus"
        case .verified: return "checkmark.seal.fill"
        // An empty seal reads as "a seal", not as one taken back.
        case .unverified: return "xmark.seal"
        case .none: return "bell"
        }
    }
}

/// `app.bsky.actor.profile`. Unknown keys are not preserved, but the fields the
/// app can edit are all of them today.
struct ProfileRecord: Codable {
    var type: String = "app.bsky.actor.profile"
    var displayName: String?
    var description: String?
    var avatar: BlobRef?
    var banner: BlobRef?

    enum CodingKeys: String, CodingKey {
        case type = "$type", displayName, description, avatar, banner
    }
}

// MARK: - Direct messages

struct ConvoListResponse: Decodable {
    let convos: [Convo]
    let cursor: String?
}

/// A conversation. Members always include the signed-in account, so the other
/// side has to be picked out for display.
struct Convo: Decodable, Identifiable, Hashable {
    let id: String
    let rev: String
    var members: [ActorProfile]
    var lastMessage: Message?
    var unreadCount: Int?
    /// Quiet, without the other side being told.
    var muted: Bool?

    struct Message: Decodable, Hashable {
        var id: String?
        var text: String?
        var sentAt: String?
        var sender: Sender?

        struct Sender: Decodable, Hashable { let did: String }
    }

    func partner(excluding did: String?) -> ActorProfile? {
        members.first { $0.did != did } ?? members.first
    }
}

struct MessageListResponse: Decodable {
    let messages: [ChatMessage]
    let cursor: String?
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    var rev: String?
    var text: String
    var sentAt: String?
    var sender: Convo.Message.Sender?

    func isMine(_ did: String?) -> Bool { sender?.did == did }
}

// MARK: - Video jobs

struct VideoJobResponse: Decodable {
    let jobStatus: VideoJob
}

/// A video being processed by the video service.
struct VideoJob: Decodable {
    let jobId: String
    let state: String
    var progress: Int?
    var blob: BlobRef?
    var error: String?
    var message: String?

    var isFinished: Bool { state == "JOB_STATE_COMPLETED" }
    var isFailed: Bool { state == "JOB_STATE_FAILED" }
}

/// What the service is willing to take right now.
struct VideoUploadLimits: Decodable {
    var canUpload: Bool
    var remainingDailyVideos: Int?
    var remainingDailyBytes: Int?
    var message: String?
    var error: String?
}

// MARK: - Moderation

/// What a report is about: a whole account, or one record.
enum ReportSubject: Encodable {
    case account(did: String)
    case record(uri: String, cid: String)
    /// A single message. It has no URI, so it is named by the conversation it
    /// sits in, the message itself, and who wrote it.
    case message(convoId: String, messageId: String, did: String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type", did, uri, cid, convoId, messageId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .account(let did):
            try container.encode("com.atproto.admin.defs#repoRef", forKey: .type)
            try container.encode(did, forKey: .did)
        case .record(let uri, let cid):
            try container.encode("com.atproto.repo.strongRef", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(cid, forKey: .cid)
        case .message(let convoId, let messageId, let did):
            try container.encode("chat.bsky.convo.defs#messageRef", forKey: .type)
            try container.encode(convoId, forKey: .convoId)
            try container.encode(messageId, forKey: .messageId)
            try container.encode(did, forKey: .did)
        }
    }
}

/// Who may start a conversation with this account.
enum MessageRule: String, CaseIterable, Identifiable, Codable {
    case all
    case following
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L(.messagesFromAll)
        case .following: return L(.messagesFromFollowing)
        case .none: return L(.messagesFromNobody)
        }
    }

    /// An account with no declaration takes messages from anyone.
    init(stored: String?) {
        self = MessageRule(rawValue: stored ?? "") ?? .all
    }
}

/// The reasons the protocol defines. The wording shown to people is separate.
enum ModerationReason: String, CaseIterable, Identifiable {
    case spam = "com.atproto.moderation.defs#reasonSpam"
    case violation = "com.atproto.moderation.defs#reasonViolation"
    case misleading = "com.atproto.moderation.defs#reasonMisleading"
    case sexual = "com.atproto.moderation.defs#reasonSexual"
    case rude = "com.atproto.moderation.defs#reasonRude"
    case other = "com.atproto.moderation.defs#reasonOther"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: return L(.reportSpam)
        case .violation: return L(.reportViolation)
        case .misleading: return L(.reportMisleading)
        case .sexual: return L(.reportSexual)
        case .rude: return L(.reportRude)
        case .other: return L(.reportOther)
        }
    }
}

// MARK: - Blobs

/// A stored file, referenced from a record. The odd key names are the protocol's.
struct BlobRef: Codable, Hashable {
    var type: String = "blob"
    var ref: Link
    var mimeType: String
    var size: Int

    struct Link: Codable, Hashable {
        var link: String

        enum CodingKeys: String, CodingKey { case link = "$link" }
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type", ref, mimeType, size
    }
}

struct UploadBlobResponse: Decodable {
    let blob: BlobRef
}

// MARK: - Repo

struct CreateRecordResponse: Codable {
    let uri: String
    let cid: String
}

// MARK: - Suche

/// Followers and follows differ only in their key, so they share one shape here.
/// One list with a page of its members.
struct ListResponse: Decodable {
    struct Item: Decodable, Identifiable {
        let subject: ActorProfile
        var id: String { subject.did }
    }
    let list: ListView
    let items: [Item]
    let cursor: String?
}

struct ActorListResponse {
    let actors: [ActorProfile]
    let cursor: String?
}

struct SearchActorsResponse: Codable {
    let actors: [ActorProfile]
    let cursor: String?
}


// MARK: - Preferences and feed generators

/// The account's saved feeds live in `app.bsky.actor.getPreferences` as one entry of a
/// heterogeneous array; everything else in there is ignored on purpose.
struct PreferencesResponse: Decodable {
    let savedFeeds: [SavedFeed]

    private enum CodingKeys: String, CodingKey { case preferences }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .preferences)
        var found: [SavedFeed] = []

        while !list.isAtEnd {
            if let entry = try? list.decode(SavedFeedsPref.self), entry.type == "app.bsky.actor.defs#savedFeedsPrefV2" {
                found = entry.items
            } else {
                _ = try? list.decode(Skip.self)
            }
        }
        savedFeeds = found
    }

    private struct SavedFeedsPref: Decodable {
        let type: String
        let items: [SavedFeed]
        private enum CodingKeys: String, CodingKey { case type = "$type", items }
    }

    /// Consumes one unknown element so decoding can continue.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws { _ = try decoder.singleValueContainer() }
    }
}

struct SavedFeed: Codable, Hashable, Identifiable {
    let id: String
    /// timeline | feed | list
    let type: String
    let value: String
    let pinned: Bool
}

struct FeedGeneratorsResponse: Decodable {
    let feeds: [FeedGeneratorView]
}

struct FeedGeneratorView: Codable, Hashable, Identifiable {
    let uri: String
    var displayName: String
    var description: String?
    var avatar: String?
    var likeCount: Int?

    var id: String { uri }
}

struct ListsResponse: Decodable {
    let lists: [ListView]
    var cursor: String?
}

struct ListView: Codable, Hashable, Identifiable {
    let uri: String
    var name: String
    var description: String?
    var avatar: String?
    /// Whether the list exists to moderate or to read.
    var purpose: String?
    var listItemCount: Int?
    var creator: ActorProfile?
    var viewer: Viewer?

    var id: String { uri }
    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
    var isModeration: Bool { purpose?.hasSuffix("modlist") ?? false }

    struct Viewer: Codable, Hashable {
        var muted: Bool?
        /// URI of the block record, when the whole list is blocked.
        var blocked: String?
    }
}
