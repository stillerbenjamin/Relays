//
//  Jetstream.swift
//  Relays
//
//  A live read of the network's firehose. Jetstream is the JSON flavour of the
//  relay feed: public, unauthenticated, every record on the network as it is written.
//

import Foundation

/// One record off the firehose. No profile, no counts — just what was committed.
struct RadarEvent: Identifiable, Hashable {

    enum Kind: String, Hashable {
        case post, like, repost, follow

        var collection: String {
            switch self {
            case .post: return "app.bsky.feed.post"
            case .like: return "app.bsky.feed.like"
            case .repost: return "app.bsky.feed.repost"
            case .follow: return "app.bsky.graph.follow"
            }
        }

        var symbol: String {
            switch self {
            case .post: return "text.alignleft"
            case .like: return "heart.fill"
            case .repost: return "arrow.2.squarepath"
            case .follow: return "person.fill.badge.plus"
            }
        }

        init?(collection: String) {
            switch collection {
            case "app.bsky.feed.post": self = .post
            case "app.bsky.feed.like": self = .like
            case "app.bsky.feed.repost": self = .repost
            case "app.bsky.graph.follow": self = .follow
            default: return nil
            }
        }
    }

    let did: String
    let rkey: String
    let cid: String?
    let kind: Kind
    let text: String
    /// The record this one points at: an AT URI for likes and reposts, a DID for follows.
    let subject: String?
    let langs: [String]
    let hasMedia: Bool
    let createdAt: String?
    let receivedAt: Date

    var id: String { "\(did)/\(kind.rawValue)/\(rkey)" }
    var uri: String { "at://\(did)/\(kind.collection)/\(rkey)" }

    /// Where a tap should lead: the post itself, or the post that was liked.
    var threadURI: String? {
        switch kind {
        case .post: return uri
        case .like, .repost: return subject
        case .follow: return nil
        }
    }

    var shortDID: String {
        did.hasPrefix("did:plc:") ? String(did.dropFirst("did:plc:".count).prefix(10)) : did
    }
}

/// Which slice of the firehose to subscribe to.
enum RadarStream: String, CaseIterable, Identifiable, Codable {
    case posts, likes, reposts, follows, all

    var id: String { rawValue }

    var collections: [String] {
        switch self {
        case .posts: return [RadarEvent.Kind.post.collection]
        case .likes: return [RadarEvent.Kind.like.collection]
        case .reposts: return [RadarEvent.Kind.repost.collection]
        case .follows: return [RadarEvent.Kind.follow.collection]
        case .all: return RadarEvent.Kind.allCollections
        }
    }

    var label: String {
        switch self {
        case .posts: return L(.radarPosts)
        case .likes: return L(.radarLikes)
        case .reposts: return L(.radarReposts)
        case .follows: return L(.radarFollows)
        case .all: return L(.radarAll)
        }
    }

    /// Only posts carry text and language, so those filters make sense there.
    var carriesText: Bool { self == .posts || self == .all }
}

extension RadarEvent.Kind {
    static var allCollections: [String] {
        [Self.post, .like, .repost, .follow].map(\.collection)
    }
}

enum JetstreamHost: String, CaseIterable, Identifiable, Codable {
    case usEast1 = "jetstream1.us-east.bsky.network"
    case usEast2 = "jetstream2.us-east.bsky.network"
    case usWest1 = "jetstream1.us-west.bsky.network"
    case usWest2 = "jetstream2.us-west.bsky.network"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .usEast1: return "us-east-1"
        case .usEast2: return "us-east-2"
        case .usWest1: return "us-west-1"
        case .usWest2: return "us-west-2"
        }
    }
}

/// Wraps the websocket. Emits decoded events to whoever set the handlers.
actor JetstreamClient {

    enum State: Equatable {
        case idle
        case connecting
        case live
        case failed(String)
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var host: JetstreamHost = .usEast2
    private var stream: RadarStream = .posts
    private var attempt = 0
    private var isStopping = false

    private var onEvent: (@Sendable (RadarEvent) -> Void)?
    private var onState: (@Sendable (State) -> Void)?

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    func setHandlers(event: @escaping @Sendable (RadarEvent) -> Void,
                     state: @escaping @Sendable (State) -> Void) {
        onEvent = event
        onState = state
    }

    func setHost(_ host: JetstreamHost) {
        guard host != self.host else { return }
        self.host = host
        reconnectIfRunning()
    }

    func setStream(_ stream: RadarStream) {
        guard stream != self.stream else { return }
        self.stream = stream
        reconnectIfRunning()
    }

    private func reconnectIfRunning() {
        guard task != nil else { return }
        stop()
        start()
    }

    func start() {
        guard task == nil else { return }
        isStopping = false
        attempt = 0
        connect()
    }

    func stop() {
        isStopping = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onState?(.idle)
    }

    private func connect() {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host.rawValue
        components.path = "/subscribe"
        components.queryItems = stream.collections.map {
            URLQueryItem(name: "wantedCollections", value: $0)
        }
        guard let url = components.url else {
            onState?(.failed(L10n.t(.errorInvalidURL)))
            return
        }

        onState?(.connecting)
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receive(on: socket)
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            guard let self else { return }
            Task { await self.handle(result, from: socket) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, Error>,
                        from socket: URLSessionWebSocketTask) {
        guard !isStopping, socket === task else { return }

        switch result {
        case .success(let message):
            if attempt != 0 { attempt = 0 }
            onState?(.live)

            let data: Data?
            switch message {
            case .data(let raw): data = raw
            case .string(let text): data = text.data(using: .utf8)
            @unknown default: data = nil
            }
            if let data, let event = Self.decode(data) {
                onEvent?(event)
            }
            receive(on: socket)

        case .failure(let error):
            task = nil
            onState?(.failed(error.localizedDescription))
            scheduleReconnect()
        }
    }

    /// Exponential backoff, capped — the firehose is not worth hammering.
    private func scheduleReconnect() {
        guard !isStopping else { return }
        attempt += 1
        let delay = min(30.0, pow(2.0, Double(min(attempt, 5))))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, await !self.isStopping, await self.task == nil else { return }
            await self.connect()
        }
    }

    private static func decode(_ data: Data) -> RadarEvent? {
        struct Event: Decodable {
            struct Commit: Decodable {
                struct Record: Decodable {
                    struct Subject: Decodable { let uri: String? }
                    struct Embed: Decodable { let type: String?
                        private enum CodingKeys: String, CodingKey { case type = "$type" } }

                    let text: String?
                    let langs: [String]?
                    let createdAt: String?
                    let subject: SubjectValue?
                    let embed: Embed?
                }
                let operation: String?
                let collection: String?
                let rkey: String?
                let cid: String?
                let record: Record?
            }
            let did: String
            let kind: String?
            let commit: Commit?
        }

        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.kind == "commit",
              let commit = event.commit,
              commit.operation == "create",
              let collection = commit.collection,
              let kind = RadarEvent.Kind(collection: collection),
              let rkey = commit.rkey
        else { return nil }

        // Posts must carry text; the other kinds carry a subject instead.
        let text = commit.record?.text ?? ""
        if kind == .post && text.isEmpty { return nil }

        let embedType = commit.record?.embed?.type ?? ""
        let hasMedia = embedType.contains("images") || embedType.contains("video")

        return RadarEvent(did: event.did,
                          rkey: rkey,
                          cid: commit.cid,
                          kind: kind,
                          text: text,
                          subject: commit.record?.subject?.value,
                          langs: commit.record?.langs ?? [],
                          hasMedia: hasMedia,
                          createdAt: commit.record?.createdAt,
                          receivedAt: Date())
    }
}

/// `subject` is a DID string for follows and an object with a URI for likes and reposts.
struct SubjectValue: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            value = text
            return
        }
        struct Reference: Decodable { let uri: String? }
        value = (try? Reference(from: decoder))?.uri
    }
}
