//
//  ATProtoClient.swift
//  Relays
//
//  Thin XRPC client for the AT Protocol. Handles auth headers, automatic token
//  refresh and decoding of the lexicon responses.
//

import Foundation

enum ATProtoError: LocalizedError {
    case invalidURL
    /// The signed-in credential is not allowed to use direct messages.
    case chatNotPermitted
    case transport(Error)
    /// There was no way out of the device at all.
    case offline
    case server(status: Int, error: String?, message: String?)
    case decoding(Error)
    case notAuthenticated
    /// The stored credential no longer works and refreshing did not help — the
    /// app password was revoked, or the session was ended elsewhere.
    case sessionExpired
    /// The video service refused the file or gave up on it.
    case videoFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.t(.errorInvalidURL)
        case .chatNotPermitted:
            return L10n.t(.errorChatNotPermitted)
        case .sessionExpired:
            return L10n.t(.errorSessionExpired)
        case .videoFailed(let reason):
            if let reason, !reason.isEmpty { return reason }
            return L10n.t(.composeVideoFailed)
        case .offline:
            return L10n.t(.errorOffline)
        case .transport:
            return L10n.t(.errorTransport)
        case .server(let status, let error, let message):
            if status == 429 { return L10n.t(.errorRateLimited) }
            if let message, !message.isEmpty { return message }
            if let error, !error.isEmpty { return error }
            return L10n.t(.errorServer, status)
        case .decoding:
            return L10n.t(.errorDecoding)
        case .notAuthenticated:
            return L10n.t(.errorUnauthenticated)
        }
    }
}

actor ATProtoClient {
    static let defaultService = "https://bsky.social"

    private var service: String
    private var session: ATSession?

    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Called whenever tokens were refreshed, so the keychain stays current.
    var onSessionChange: (@Sendable (ATSession?) -> Void)?

    /// `configuration` exists so tests can put a stub transport underneath;
    /// the app always uses the default.
    init(service: String = ATProtoClient.defaultService,
         session: ATSession? = nil,
         configuration: URLSessionConfiguration? = nil) {
        self.service = service
        self.session = session

        let config = configuration ?? {
            let base = URLSessionConfiguration.default
            base.waitsForConnectivity = true
            base.timeoutIntervalForRequest = 30
            return base
        }()
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Configuration

    func setService(_ service: String) {
        self.service = Self.normalizeService(service)
    }

    func setSession(_ session: ATSession?) {
        self.session = session
    }

    func setSessionChangeHandler(_ handler: @escaping @Sendable (ATSession?) -> Void) {
        self.onSessionChange = handler
    }

    var currentSession: ATSession? { session }

    static func normalizeService(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return defaultService }
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    // MARK: - Auth

    // MARK: - The relay's register

    /// Every server the relay consumes from. Public and unauthenticated, and
    /// addressed to a relay rather than to the account's own server — so it does
    /// not go through `send`, which targets the PDS.
    nonisolated static func relayHosts(relay: RelayHostName = .default,
                                       cursor: String? = nil, limit: Int = 1_000,
                                       session: URLSession = .shared) async throws -> HostPage {
        guard var components = URLComponents(
            string: "\(relay.url)/xrpc/com.atproto.sync.listHosts") else {
            throw ATProtoError.invalidURL
        }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = query

        guard let url = components.url else { throw ATProtoError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }
        do {
            return try JSONDecoder().decode(HostPage.self, from: data)
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    /// What the relay currently thinks of one server. This is the relay's view,
    /// which lags and which only speaks for itself — worth saying wherever it
    /// is shown.
    nonisolated static func hostStatus(hostname: String, relay: RelayHostName = .default,
                                       session: URLSession = .shared) async throws -> RelayHost {
        guard var components = URLComponents(
            string: "\(relay.url)/xrpc/com.atproto.sync.getHostStatus") else {
            throw ATProtoError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "hostname", value: hostname)]
        guard let url = components.url else { throw ATProtoError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }
        do {
            return try JSONDecoder().decode(RelayHost.self, from: data)
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    // MARK: - Asking a server about itself

    /// What a server requires of a new account. Public, and the only honest way
    /// to build a form: the requirements differ per server and change over time.
    nonisolated static func describeServer(host: String,
                                           session: URLSession = .shared) async throws -> ServerDescription {
        let normalized = normalizeService(host)
        guard let url = URL(string: "\(normalized)/xrpc/com.atproto.server.describeServer") else {
            throw ATProtoError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }
        do {
            return try JSONDecoder().decode(ServerDescription.self, from: data)
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    /// An app password, made here for another client or another device.
    ///
    /// The server returns it once and never again — there is no endpoint that
    /// reads one back — so whatever asks for it has to put it in front of
    /// somebody immediately.
    ///
    /// `privileged` is what direct messages need; a server that does not know
    /// the flag has to be able to answer the same call without it.
    func createAppPassword(name: String, privileged: Bool) async throws -> String {
        struct Body: Encodable { let name: String; let privileged: Bool? }
        struct Response: Decodable { let password: String }

        do {
            let response: Response = try await send("com.atproto.server.createAppPassword",
                                                    method: .post,
                                                    body: Body(name: name, privileged: privileged))
            return response.password
        } catch {
            guard privileged else { throw error }
            // Older servers reject the flag rather than ignoring it. A password
            // without message access is still better than no account.
            let response: Response = try await send("com.atproto.server.createAppPassword",
                                                    method: .post,
                                                    body: Body(name: name, privileged: nil))
            return response.password
        }
    }

    /// The app passwords on this account. Names and dates only — the passwords
    /// themselves are shown once, when they are made, and never again.
    func appPasswords() async throws -> [AppPassword] {
        struct Response: Decodable { let passwords: [AppPassword] }
        let response: Response = try await send("com.atproto.server.listAppPasswords")
        return response.passwords
    }

    /// Takes one back. Anything signed in with it stops working at once —
    /// including this app, if this is the one it is using.
    func revokeAppPassword(name: String) async throws {
        struct Body: Encodable { let name: String }
        try await sendVoid("com.atproto.server.revokeAppPassword", method: .post,
                           body: Body(name: name))
    }

    // MARK: - Unmaking one

    /// Sends the code that deleting an account requires, by email.
    func requestAccountDelete() async throws {
        try await sendVoid("com.atproto.server.requestAccountDelete", method: .post)
    }

    /// Irreversible. The DID stays in the network's history; everything the
    /// account holds does not.
    func deleteAccount(did: String, password: String, token: String) async throws {
        struct Body: Encodable { let did: String; let password: String; let token: String }
        try await sendVoid("com.atproto.server.deleteAccount", method: .post,
                           body: Body(did: did, password: password, token: token),
                           authenticated: false)
    }

    func createSession(identifier: String, password: String) async throws -> ATSession {
        struct Body: Encodable { let identifier: String; let password: String }
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        var new: ATSession = try await send(
            "com.atproto.server.createSession",
            method: .post,
            body: Body(identifier: cleaned, password: password.trimmingCharacters(in: .whitespacesAndNewlines)),
            authenticated: false
        )
        new.service = service
        session = new
        onSessionChange?(new)
        return new
    }

    @discardableResult
    func refreshSession() async throws -> ATSession {
        guard let refreshJwt = session?.refreshJwt else { throw ATProtoError.notAuthenticated }
        var new: ATSession = try await send(
            "com.atproto.server.refreshSession",
            method: .post,
            authenticated: false,
            bearer: refreshJwt
        )
        new.service = service
        session = new
        onSessionChange?(new)
        return new
    }

    func logout() async {
        if let refreshJwt = session?.refreshJwt {
            _ = try? await sendVoid("com.atproto.server.deleteSession", method: .post, authenticated: false, bearer: refreshJwt)
        }
        session = nil
        onSessionChange?(nil)
    }

    // MARK: - Feeds

    func timeline(cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        try await send("app.bsky.feed.getTimeline", query: [
            "limit": String(limit),
            "cursor": cursor
        ])
    }

    /// `filter` is the lexicon's own vocabulary: posts_no_replies,
    /// posts_with_replies, posts_with_media.
    func authorFeed(actor: String, filter: String? = nil,
                    cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        try await send("app.bsky.feed.getAuthorFeed", query: [
            "actor": actor,
            "filter": filter,
            "limit": String(limit),
            "cursor": cursor
        ])
    }

    /// A custom feed produced by a feed generator.
    func customFeed(uri: String, cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        try await send("app.bsky.feed.getFeed", query: [
            "feed": uri,
            "limit": String(limit),
            "cursor": cursor
        ])
    }

    /// Posts by the members of a curated list.
    func listFeed(uri: String, cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        try await send("app.bsky.feed.getListFeed", query: [
            "list": uri,
            "limit": String(limit),
            "cursor": cursor
        ])
    }

    /// Feeds and lists the account has saved, in the order it saved them.
    func savedFeeds() async throws -> [SavedFeed] {
        let response: PreferencesResponse = try await send("app.bsky.actor.getPreferences")
        return response.savedFeeds
    }

    /// Feeds other people have found worth keeping. Public — this is the one
    /// discovery surface that works before anybody has followed anyone.
    func popularFeeds(limit: Int = 20) async throws -> [FeedGeneratorView] {
        struct Response: Decodable { let feeds: [FeedGeneratorView] }
        let response: Response = try await send("app.bsky.unspecced.getPopularFeedGenerators",
                                                query: ["limit": String(limit)])
        return response.feeds
    }

    /// Accounts the network suggests for this reader. Needs the session — the
    /// suggestion is about them.
    func suggestedActors(limit: Int = 20) async throws -> [ActorProfile] {
        struct Response: Decodable { let actors: [ActorProfile] }
        let response: Response = try await send("app.bsky.actor.getSuggestions",
                                                query: ["limit": String(limit)])
        return response.actors
    }

    /// The posts that quote this one. The count sits on the repost control; this
    /// is what is behind it.
    func quotes(of uri: String, cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        struct Response: Decodable { let posts: [PostView]; let cursor: String? }
        var query = ["uri": uri, "limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        let response: Response = try await send("app.bsky.feed.getQuotes", query: query)
        return FeedResponse(feed: response.posts.map { FeedViewPost(post: $0, reply: nil, reason: nil) },
                            cursor: response.cursor)
    }

    /// Who liked a post. The count sits on the heart, and the heart has to stay
    /// a one-tap toggle — so this is reached from the menu, not from the number.
    func likes(of uri: String, cursor: String? = nil, limit: Int = 50) async throws -> ActorListResponse {
        // The two lists do not have the same shape: a like carries its account
        // nested under `actor`, a repost is the account. One decoder over both
        // would be wrong.
        struct Like: Decodable { let actor: ActorProfile }
        struct Response: Decodable { let likes: [Like]; let cursor: String? }
        let response: Response = try await send("app.bsky.feed.getLikes", query: [
            "uri": uri, "limit": String(limit), "cursor": cursor
        ])
        return ActorListResponse(actors: response.likes.map(\.actor), cursor: response.cursor)
    }

    /// Who reposted a post.
    func repostedBy(uri: String, cursor: String? = nil, limit: Int = 50) async throws -> ActorListResponse {
        struct Response: Decodable { let repostedBy: [ActorProfile]; let cursor: String? }
        let response: Response = try await send("app.bsky.feed.getRepostedBy", query: [
            "uri": uri, "limit": String(limit), "cursor": cursor
        ])
        return ActorListResponse(actors: response.repostedBy, cursor: response.cursor)
    }

    func feedGenerators(uris: [String]) async throws -> [FeedGeneratorView] {
        guard !uris.isEmpty else { return [] }
        let items = uris.prefix(25).map { URLQueryItem(name: "feeds", value: $0) }
        let response: FeedGeneratorsResponse = try await send("app.bsky.feed.getFeedGenerators", repeatedQuery: items)
        return response.feeds
    }

    func list(uri: String) async throws -> ListView {
        struct Response: Decodable { let list: ListView }
        let response: Response = try await send("app.bsky.graph.getList", query: ["list": uri, "limit": "1"])
        return response.list
    }

    func thread(uri: String, depth: Int = 12) async throws -> ThreadResponse {
        try await send("app.bsky.feed.getPostThread", query: [
            "uri": uri,
            "depth": String(depth)
        ])
    }

    /// The raw record behind a post, pretty-printed for the inspector.
    func rawRecord(uri: String) async throws -> String {
        let parts = uri.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw ATProtoError.invalidURL }
        let rkey = parts[parts.count - 1]
        let collection = parts[parts.count - 2]
        guard let repo = parts.first(where: { $0.hasPrefix("did:") }) else { throw ATProtoError.invalidURL }

        let data = try await perform("com.atproto.repo.getRecord", method: .get,
                                     query: ["repo": repo, "collection": collection, "rkey": rkey],
                                     body: nil, authenticated: true, bearer: nil)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return text
    }

    // MARK: - Actor

    func profile(actor: String) async throws -> ActorProfile {
        try await send("app.bsky.actor.getProfile", query: ["actor": actor])
    }

    /// Batch profile lookup — the firehose hands out DIDs, not handles.
    func profiles(actors: [String]) async throws -> [ActorProfile] {
        guard !actors.isEmpty else { return [] }
        struct Response: Decodable { let profiles: [ActorProfile] }
        let items = actors.prefix(25).map { URLQueryItem(name: "actors", value: $0) }
        let response: Response = try await send("app.bsky.actor.getProfiles", repeatedQuery: items)
        return response.profiles
    }

    /// Accounts following this actor.
    func followers(actor: String, cursor: String? = nil, limit: Int = 50) async throws -> ActorListResponse {
        struct Response: Decodable {
            let followers: [ActorProfile]
            let cursor: String?
        }
        let response: Response = try await send("app.bsky.graph.getFollowers", query: [
            "actor": actor, "limit": String(limit), "cursor": cursor
        ])
        return ActorListResponse(actors: response.followers, cursor: response.cursor)
    }

    /// Accounts this actor follows.
    func follows(actor: String, cursor: String? = nil, limit: Int = 50) async throws -> ActorListResponse {
        struct Response: Decodable {
            let follows: [ActorProfile]
            let cursor: String?
        }
        let response: Response = try await send("app.bsky.graph.getFollows", query: [
            "actor": actor, "limit": String(limit), "cursor": cursor
        ])
        return ActorListResponse(actors: response.follows, cursor: response.cursor)
    }

    /// Handle to DID. Mentions are stored as DIDs, so a name that is typed has to
    /// be resolved before the post can carry it.
    func resolveHandle(_ handle: String) async throws -> String {
        struct Response: Decodable { let did: String }
        let response: Response = try await send("com.atproto.identity.resolveHandle",
                                                query: ["handle": handle])
        return response.did
    }

    /// Suggestions while typing a mention.
    func typeahead(term: String, limit: Int = 8) async throws -> [ActorProfile] {
        struct Response: Decodable { let actors: [ActorProfile] }
        let response: Response = try await send("app.bsky.actor.searchActorsTypeahead",
                                                query: ["q": term, "limit": String(limit)])
        return response.actors
    }

    /// Full-text post search. A hashtag is just a query beginning with '#'.
    func searchPosts(term: String, cursor: String? = nil, limit: Int = 30) async throws -> FeedResponse {
        struct Response: Decodable {
            let posts: [PostView]
            let cursor: String?
        }
        let response: Response = try await send("app.bsky.feed.searchPosts", query: [
            "q": term, "limit": String(limit), "cursor": cursor
        ])
        // Search returns bare posts; the feed views the app works with wrap them.
        return FeedResponse(feed: response.posts.map { FeedViewPost(post: $0, reply: nil, reason: nil) },
                            cursor: response.cursor)
    }

    func searchActors(term: String, limit: Int = 25) async throws -> SearchActorsResponse {
        try await send("app.bsky.actor.searchActors", query: [
            "q": term,
            "limit": String(limit)
        ])
    }

    // MARK: - Notifications

    func notifications(cursor: String? = nil, limit: Int = 40) async throws -> NotificationsResponse {
        try await send("app.bsky.notification.listNotifications", query: [
            "limit": String(limit),
            "cursor": cursor
        ])
    }

    func unreadCount() async throws -> Int {
        struct Response: Codable { let count: Int }
        let response: Response = try await send("app.bsky.notification.getUnreadCount")
        return response.count
    }

    /// What reaches this account, on the account. Twelve kinds, each with two
    /// switches and — for eight of them — an audience.
    func notificationPreferences() async throws -> NotificationPreferences {
        struct Response: Decodable { let preferences: NotificationPreferences }
        let response: Response = try await send("app.bsky.notification.getPreferences")
        return response.preferences
    }

    /// Always sends all twelve. The lexicon does not promise that omitted keys
    /// are left alone — unlike the chat one, which says so explicitly — and
    /// sending the whole set from loaded state makes the question moot.
    @discardableResult
    func setNotificationPreferences(_ preferences: NotificationPreferences)
    async throws -> NotificationPreferences {
        struct Response: Decodable { let preferences: NotificationPreferences }
        let response: Response = try await send("app.bsky.notification.putPreferencesV2",
                                                method: .post, body: preferences)
        return response.preferences
    }

    func markNotificationsSeen() async throws {
        struct Body: Encodable { let seenAt: String }
        try await sendVoid("app.bsky.notification.updateSeen", method: .post,
                           body: Body(seenAt: Self.timestamp()))
    }

    // MARK: - Writing records

    /// Uploads one file and returns the reference a record can embed.
    func uploadBlob(data: Data, mimeType: String) async throws -> BlobRef {
        guard let url = URL(string: "\(service)/xrpc/com.atproto.repo.uploadBlob") else {
            throw ATProtoError.invalidURL
        }
        guard let token = session?.accessJwt else { throw ATProtoError.notAuthenticated }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (body, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }

        // "did:plc:a;redact, did:plc:b" — the flag marks one that is applied
        // whether or not it was asked for.
        if let applied = http.value(forHTTPHeaderField: "atproto-content-labelers") {
            appliedLabelers = applied
                .split(separator: ",")
                .map { $0.split(separator: ";").first.map(String.init) ?? String($0) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("did:") }
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(ErrorPayload.self, from: body)
            throw ATProtoError.server(status: http.statusCode,
                                      error: payload?.error, message: payload?.message)
        }
        return try decoder.decode(UploadBlobResponse.self, from: body).blob
    }

    /// A quoted post, on its own or alongside pictures.
    struct RecordEmbed: Encodable {
        let type = "app.bsky.embed.record"
        let record: StrongRef

        enum CodingKeys: String, CodingKey { case type = "$type", record }
    }

    /// Pictures and a quote in one post have their own wrapper in the lexicon.
    struct RecordWithMediaEmbed: Encodable {
        let type = "app.bsky.embed.recordWithMedia"
        let record: RecordEmbed
        let media: ImagesEmbed

        enum CodingKeys: String, CodingKey { case type = "$type", record, media }
    }

    /// Which embed a post carries. Encoding is transparent: the wrapper writes
    /// whichever shape it holds, so the record ends up with one `embed` key.
    enum PostEmbedPayload: Encodable {
        case images(ImagesEmbed)
        case video(VideoEmbed)
        case quote(RecordEmbed)
        case quoteWithImages(RecordWithMediaEmbed)
        case external(ExternalEmbed)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .images(let embed): try embed.encode(to: encoder)
            case .video(let embed): try embed.encode(to: encoder)
            case .quote(let embed): try embed.encode(to: encoder)
            case .quoteWithImages(let embed): try embed.encode(to: encoder)
            case .external(let embed): try embed.encode(to: encoder)
            }
        }

        /// Builds the right shape from what the composer has. A video and pictures
        /// cannot travel together, so the video wins if both are somehow present.
        static func make(images: ImagesEmbed?, video: VideoEmbed? = nil,
                         quoting: StrongRef?, link: ExternalEmbed? = nil) -> PostEmbedPayload? {
            if let video { return .video(video) }
            // A post carries one embed. Anything the author put there on purpose
            // outranks a card the app offered by itself, so the link goes last.
            if images == nil, quoting == nil, let link { return .external(link) }
            switch (images, quoting) {
            case (let images?, let quote?):
                return .quoteWithImages(RecordWithMediaEmbed(record: RecordEmbed(record: quote),
                                                             media: images))
            case (let images?, nil):
                return .images(images)
            case (nil, let quote?):
                return .quote(RecordEmbed(record: quote))
            case (nil, nil):
                return nil
            }
        }
    }

    /// The images embed as the lexicon defines it.
    struct ImagesEmbed: Encodable {
        let type = "app.bsky.embed.images"
        let images: [Item]

        struct Item: Encodable {
            let image: BlobRef
            let alt: String
            let aspectRatio: EmbedImage.AspectRatio?
        }

        enum CodingKeys: String, CodingKey { case type = "$type", images }
    }

    /// `app.bsky.embed.external` — the card a link carries in a post.
    struct ExternalEmbed: Encodable {
        let type = "app.bsky.embed.external"
        let external: Item

        struct Item: Encodable {
            let uri: String
            let title: String
            let description: String
            /// Optional: a card with no picture is still a card.
            let thumb: BlobRef?
        }

        enum CodingKeys: String, CodingKey { case type = "$type", external }
    }

    /// Reads a page's own description of itself and uploads its picture, so the
    /// post can carry a card. Returns nil rather than throwing: a link that will
    /// not answer is not a reason to refuse the post.
    func linkCard(for url: URL) async -> LinkCard? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Some sites serve a different page to something that does not look like
        // a browser, and a few refuse outright.
        request.setValue("Mozilla/5.0 (compatible; Relays/1.0; +https://github.com/stillerbenjamin/Relays)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }

        // Only the head is needed, and an unbounded read of somebody else's URL
        // is not something a composer should do.
        let head = data.prefix(LinkCardReader.limit)
        guard let html = String(data: head, encoding: .utf8)
                ?? String(data: head, encoding: .isoLatin1) else { return nil }

        let final = http.url ?? url
        let card = LinkCardReader.card(from: html, url: final)
        return card.isWorthShowing ? card : nil
    }

    /// Turns a read card into the embed a post carries, uploading the picture as
    /// a blob. A picture that will not fetch or will not compress is dropped and
    /// the card goes without it.
    func externalEmbed(from card: LinkCard,
                       thumbnail: @Sendable (Data) async -> (data: Data, mime: String)?)
    async -> ExternalEmbed {
        var blob: BlobRef?
        if let imageURL = card.imageURL,
           let (data, _) = try? await URLSession.shared.data(from: imageURL),
           let prepared = await thumbnail(data) {
            blob = try? await uploadBlob(data: prepared.data, mimeType: prepared.mime)
        }
        return ExternalEmbed(external: .init(uri: card.uri,
                                             title: card.title ?? card.uri,
                                             description: card.description ?? "",
                                             thumb: blob))
    }

    @discardableResult
    func createPost(text: String, reply: PostRecord.ReplyRefStrong? = nil,
                    embed: PostEmbedPayload? = nil) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.feed.post"
            let text: String
            let createdAt: String
            let langs: [String]?
            let facets: [Facet]?
            let reply: PostRecord.ReplyRefStrong?
            let embed: PostEmbedPayload?

            enum CodingKeys: String, CodingKey {
                case type = "$type", text, createdAt, langs, facets, reply, embed
            }
        }

        // Links and tags are found locally; mentions need the network to turn a
        // handle into the DID the record stores. Names that will not resolve are
        // left as plain text rather than failing the post.
        var facets = RichText.detectFacets(in: text)
        for candidate in RichText.mentionCandidates(in: text) {
            guard let did = try? await resolveHandle(candidate.handle) else { continue }
            facets.append(Facet(index: candidate.index, features: [.mention(did: did)]))
        }
        facets.sort { $0.index.byteStart < $1.index.byteStart }

        let record = Record(
            text: text,
            createdAt: Self.timestamp(),
            langs: [Locale.current.language.languageCode?.identifier ?? "en"],
            facets: facets.isEmpty ? nil : facets,
            reply: reply,
            embed: embed
        )
        return try await createRecord(collection: "app.bsky.feed.post", record: record)
    }

    @discardableResult
    func like(uri: String, cid: String) async throws -> CreateRecordResponse {
        try await createRecord(collection: "app.bsky.feed.like",
                               record: SubjectRecord(type: "app.bsky.feed.like", subject: StrongRef(uri: uri, cid: cid), createdAt: Self.timestamp()))
    }

    @discardableResult
    func repost(uri: String, cid: String) async throws -> CreateRecordResponse {
        try await createRecord(collection: "app.bsky.feed.repost",
                               record: SubjectRecord(type: "app.bsky.feed.repost", subject: StrongRef(uri: uri, cid: cid), createdAt: Self.timestamp()))
    }

    @discardableResult
    func follow(did: String) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.graph.follow"
            let subject: String
            let createdAt: String
            enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }
        }
        return try await createRecord(collection: "app.bsky.graph.follow",
                                      record: Record(subject: did, createdAt: Self.timestamp()))
    }

    // MARK: - Direct messages

    /// Chat is a service of its own, like video: same session, different host,
    /// reached with a token the PDS mints for that audience.
    private func chatRequest(_ endpoint: String, method: Method,
                             query: [String: String?] = [:],
                             body: (any Encodable)? = nil) async throws -> Data {
        let token: String
        do {
            token = try await serviceAuth(audience: "did:web:api.bsky.chat", method: endpoint)
        } catch let error as ATProtoError {
            // An ordinary app password cannot reach chat at all: the PDS refuses to
            // mint a token for it. That is a permission, not a failure, and saying
            // "insufficient access" to someone helps nobody.
            if case .server(_, _, let message) = error,
               message?.localizedCaseInsensitiveContains("insufficient access") == true {
                throw ATProtoError.chatNotPermitted
            }
            throw error
        }

        guard var components = URLComponents(string: "https://api.bsky.chat/xrpc/\(endpoint)") else {
            throw ATProtoError.invalidURL
        }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components.url else { throw ATProtoError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }

        // "did:plc:a;redact, did:plc:b" — the flag marks one that is applied
        // whether or not it was asked for.
        if let applied = http.value(forHTTPHeaderField: "atproto-content-labelers") {
            appliedLabelers = applied
                .split(separator: ",")
                .map { $0.split(separator: ";").first.map(String.init) ?? String($0) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("did:") }
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(ErrorPayload.self, from: data)
            throw ATProtoError.server(status: http.statusCode,
                                      error: payload?.error, message: payload?.message)
        }
        return data
    }

    func conversations(cursor: String? = nil, limit: Int = 30) async throws -> ConvoListResponse {
        let data = try await chatRequest("chat.bsky.convo.listConvos", method: .get,
                                         query: ["limit": String(limit), "cursor": cursor])
        return try decoder.decode(ConvoListResponse.self, from: data)
    }

    func messages(convoId: String, cursor: String? = nil, limit: Int = 50) async throws -> MessageListResponse {
        let data = try await chatRequest("chat.bsky.convo.getMessages", method: .get,
                                         query: ["convoId": convoId, "limit": String(limit), "cursor": cursor])
        return try decoder.decode(MessageListResponse.self, from: data)
    }

    @discardableResult
    func sendMessage(convoId: String, text: String) async throws -> ChatMessage {
        struct Body: Encodable {
            let convoId: String
            let message: Payload
            struct Payload: Encodable {
                let text: String
                let facets: [Facet]?
            }
        }
        let facets = RichText.detectFacets(in: text)
        let data = try await chatRequest("chat.bsky.convo.sendMessage", method: .post,
                                         body: Body(convoId: convoId,
                                                    message: .init(text: text,
                                                                   facets: facets.isEmpty ? nil : facets)))
        return try decoder.decode(ChatMessage.self, from: data)
    }

    /// Opens (or finds) the conversation with one account.
    func conversation(with did: String) async throws -> Convo {
        struct Response: Decodable { let convo: Convo }
        let data = try await chatRequest("chat.bsky.convo.getConvoForMembers", method: .get,
                                         query: ["members": did])
        return try decoder.decode(Response.self, from: data).convo
    }

    /// A conversation goes quiet without anyone being told.
    func muteConversation(convoId: String) async throws {
        struct Body: Encodable { let convoId: String }
        _ = try await chatRequest("chat.bsky.convo.muteConvo", method: .post,
                                  body: Body(convoId: convoId))
    }

    func unmuteConversation(convoId: String) async throws {
        struct Body: Encodable { let convoId: String }
        _ = try await chatRequest("chat.bsky.convo.unmuteConvo", method: .post,
                                  body: Body(convoId: convoId))
    }

    /// Leaving removes the conversation from this side only. The other person
    /// keeps their copy; nothing is deleted for them.
    func leaveConversation(convoId: String) async throws {
        struct Body: Encodable { let convoId: String }
        _ = try await chatRequest("chat.bsky.convo.leaveConvo", method: .post,
                                  body: Body(convoId: convoId))
    }

    // MARK: - Who may write

    /// The record that decides who can open a conversation. It lives at the key
    /// `self`, so there is exactly one per account.
    func messageRule() async throws -> MessageRule {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        struct Response: Decodable { let value: JSONValue }
        let response: Response = try await send(
            "com.atproto.repo.getRecord",
            query: ["repo": did, "collection": "chat.bsky.actor.declaration", "rkey": "self"])
        return MessageRule(stored: response.value.objectValue?["allowIncoming"]?.stringValue)
    }

    func setMessageRule(_ rule: MessageRule) async throws {
        try await putRecord(collection: "chat.bsky.actor.declaration", rkey: "self",
                            record: .object([
                                "$type": .string("chat.bsky.actor.declaration"),
                                "allowIncoming": .string(rule.rawValue),
                            ]))
    }

    func markConversationRead(convoId: String) async throws {
        struct Body: Encodable { let convoId: String }
        _ = try await chatRequest("chat.bsky.convo.updateRead", method: .post,
                                  body: Body(convoId: convoId))
    }

    // MARK: - Video

    /// Videos do not go to the PDS. They go to a separate service, which needs a
    /// token minted by the PDS for exactly that audience and method.
    /// A short-lived token for another service in the network.
    private func serviceAuth(audience: String, method: String) async throws -> String {
        struct Response: Decodable { let token: String }
        let response: Response = try await send("com.atproto.server.getServiceAuth", query: [
            "aud": audience,
            "lxm": method,
            "exp": String(Int(Date().addingTimeInterval(1800).timeIntervalSince1970))
        ])
        return response.token
    }

    /// Hands the file to the video service and returns the job it created.
    func uploadVideo(data: Data, filename: String) async throws -> VideoJob {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        let token = try await serviceAuth(audience: Self.videoServiceDID,
                                          method: "app.bsky.video.uploadVideo")

        var components = URLComponents(string: "\(Self.videoService)/xrpc/app.bsky.video.uploadVideo")
        components?.queryItems = [
            URLQueryItem(name: "did", value: did),
            URLQueryItem(name: "name", value: filename)
        ]
        guard let url = components?.url else { throw ATProtoError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // The service stores what it is told. A .mov announced as mp4 comes back
        // out as a file nothing will play.
        request.setValue(Self.contentType(for: filename), forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (body, response) = try await urlSession.data(for: request)
        return try Self.job(fromVideoService: body, response: response)
    }

    /// How far along one job is.
    ///
    /// This lives on the video service, not on the account's own server — the PDS
    /// has never heard of the job. Sending it there was why an upload never
    /// finished: the post waited on an answer that could not come.
    ///
    /// It needs no token: the job id is the secret.
    func videoJob(id: String) async throws -> VideoJob {
        var components = URLComponents(string: "\(Self.videoService)/xrpc/app.bsky.video.getJobStatus")
        components?.queryItems = [URLQueryItem(name: "jobId", value: id)]
        guard let url = components?.url else { throw ATProtoError.invalidURL }

        let (body, response) = try await urlSession.data(from: url)
        return try Self.job(fromVideoService: body, response: response)
    }

    /// Waits for the service to finish, reporting progress as it goes.
    func awaitVideo(job: VideoJob, progress: @escaping @Sendable (Int) -> Void) async throws -> BlobRef {
        var current = job
        var failures = 0

        for _ in 0..<150 {                       // five minutes at two seconds
            if current.isFailed {
                throw ATProtoError.videoFailed(current.message ?? current.error)
            }
            if let blob = current.blob { return blob }
            // Finished without a blob is not success, whatever the state says.
            if current.isFinished {
                throw ATProtoError.videoFailed(current.message ?? current.error)
            }

            progress(current.progress ?? 0)
            try await Task.sleep(for: .seconds(2))

            do {
                current = try await videoJob(id: current.jobId)
                failures = 0
            } catch {
                // A dropped poll is not a failed upload. The job keeps running on
                // the service; give it a few more tries before giving up.
                failures += 1
                if failures >= 5 { throw error }
            }
        }
        throw ATProtoError.videoFailed(nil)
    }

    /// What the service will take, before anything is sent up a slow connection.
    func videoUploadLimits() async throws -> VideoUploadLimits {
        let token = try await serviceAuth(audience: Self.videoServiceDID,
                                          method: "app.bsky.video.getUploadLimits")
        guard let url = URL(string: "\(Self.videoService)/xrpc/app.bsky.video.getUploadLimits") else {
            throw ATProtoError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (body, _) = try await urlSession.data(for: request)
        do {
            return try decoder.decode(VideoUploadLimits.self, from: body)
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    static let videoService = "https://video.bsky.app"
    static let videoServiceDID = "did:web:video.bsky.app"

    private static func contentType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "webm": return "video/webm"
        default: return "video/mp4"
        }
    }

    /// The video service answers with the job either wrapped in `jobStatus` or,
    /// when something went wrong, flat and with an `error` on it. Both shapes
    /// have to be read, or a refusal arrives as a decoding failure.
    private static func job(fromVideoService body: Data,
                            response: URLResponse) throws -> VideoJob {
        let decoder = JSONDecoder()

        if let wrapped = try? decoder.decode(VideoJobResponse.self, from: body) {
            return wrapped.jobStatus
        }
        if let flat = try? decoder.decode(VideoJob.self, from: body) {
            if let error = flat.error, !error.isEmpty {
                throw ATProtoError.videoFailed(flat.message ?? error)
            }
            return flat
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let payload = try? decoder.decode(ErrorPayload.self, from: body)
        throw ATProtoError.server(status: status, error: payload?.error, message: payload?.message)
    }

    /// The video embed as the lexicon defines it.
    struct VideoEmbed: Encodable {
        let type = "app.bsky.embed.video"
        let video: BlobRef
        let alt: String?
        let aspectRatio: EmbedImage.AspectRatio?

        enum CodingKeys: String, CodingKey { case type = "$type", video, alt, aspectRatio }
    }

    // MARK: - Own profile

    /// The raw profile record, which is what has to be written back — a partial
    /// update would drop fields the app does not know about.
    func profileRecord(did: String) async throws -> ProfileRecord? {
        struct Response: Decodable { let value: ProfileRecord }
        do {
            let response: Response = try await send("com.atproto.repo.getRecord", query: [
                "repo": did, "collection": "app.bsky.actor.profile", "rkey": "self"
            ])
            return response.value
        } catch ATProtoError.server(_, let error, _) where error == "RecordNotFound" {
            return nil   // A profile that was never edited has no record yet.
        }
    }

    func putProfile(did: String, record: ProfileRecord) async throws {
        struct Body: Encodable {
            let repo: String
            let collection = "app.bsky.actor.profile"
            let rkey = "self"
            let record: ProfileRecord
        }
        try await sendVoid("com.atproto.repo.putRecord", method: .post,
                           body: Body(repo: did, record: record))
    }

    // MARK: - Moderation

    /// Reports a post or an account to the moderation service the PDS points at.
    /// `labeler` routes the report to a subscribed service instead of the one
    /// the server picks. The proxy header names it, with the fragment that says
    /// which of its services is meant.
    func report(subject: ReportSubject, reason: ModerationReason, note: String?,
                labeler: String? = nil) async throws {
        struct Body: Encodable {
            let reasonType: String
            let reason: String?
            let subject: ReportSubject
        }
        try await sendVoid("com.atproto.moderation.createReport", method: .post,
                           body: Body(reasonType: reason.rawValue,
                                      reason: note?.isEmpty == false ? note : nil,
                                      subject: subject),
                           proxy: labeler.map { "\($0)#atproto_labeler" })
    }

    @discardableResult
    func block(did: String) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.graph.block"
            let subject: String
            let createdAt: String
            enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }
        }
        return try await createRecord(collection: "app.bsky.graph.block",
                                      record: Record(subject: did, createdAt: Self.timestamp()))
    }

    /// Everyone the account has muted. Muting is a server-side list, not a record,
    /// so this is the only way to know about mutes made on another client.
    // MARK: - Labelers

    /// Sent with every read so the appview includes these services' labels.
    private var acceptedLabelers: [String] = []

    /// What the server said it actually applied, from the last answer that told
    /// us. Some services cannot be declined, and the app should not pretend the
    /// subscription list is the whole truth.
    private(set) var appliedLabelers: [String] = []

    func setAcceptedLabelers(_ dids: [String]) {
        acceptedLabelers = dids
    }

    /// The services themselves, with the definitions for the values they apply.
    func labelerServices(dids: [String]) async throws -> [LabelerService] {
        guard !dids.isEmpty else { return [] }
        struct Response: Decodable { let views: [LabelerService] }
        let response: Response = try await send(
            "app.bsky.labeler.getServices",
            query: ["detailed": "true"],
            repeatedQuery: dids.map { URLQueryItem(name: "dids", value: $0) })
        return response.views
    }

    /// Labels straight from a labeler, without the appview in between. Public and
    /// unauthenticated: a labeler answers for its own labels to anyone.
    nonisolated static func queryLabels(at endpoint: URL, uris: [String],
                                        session: URLSession = .shared) async throws -> [ContentLabel] {
        guard !uris.isEmpty else { return [] }
        guard var components = URLComponents(
            url: endpoint.appendingPathComponent("xrpc/com.atproto.label.queryLabels"),
            resolvingAgainstBaseURL: false) else { throw ATProtoError.invalidURL }
        components.queryItems = uris.map { URLQueryItem(name: "uriPatterns", value: $0) }
            + [URLQueryItem(name: "limit", value: "250")]
        guard let url = components.url else { throw ATProtoError.invalidURL }

        struct Response: Decodable { let labels: [ContentLabel] }
        let (data, _) = try await session.data(from: url)
        do {
            return try JSONDecoder().decode(Response.self, from: data).labels
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    func mutes(cursor: String? = nil, limit: Int = 100) async throws -> ActorListResponse {
        struct Response: Decodable { let mutes: [ActorProfile]; let cursor: String? }
        var query = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        let response: Response = try await send("app.bsky.graph.getMutes", query: query)
        return ActorListResponse(actors: response.mutes, cursor: response.cursor)
    }

    /// Everyone the account blocks. Blocks are records, so each carries the URI
    /// that has to be deleted to lift it.
    func blocks(cursor: String? = nil, limit: Int = 100) async throws -> ActorListResponse {
        struct Response: Decodable { let blocks: [ActorProfile]; let cursor: String? }
        var query = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        let response: Response = try await send("app.bsky.graph.getBlocks", query: query)
        return ActorListResponse(actors: response.blocks, cursor: response.cursor)
    }

    /// Lists the account has muted wholesale.
    func listMutes(cursor: String? = nil, limit: Int = 50) async throws -> [String] {
        struct List: Decodable { let uri: String }
        struct Response: Decodable { let lists: [List] }
        var query = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        let response: Response = try await send("app.bsky.graph.getListMutes", query: query)
        return response.lists.map(\.uri)
    }

    // MARK: - Lists

    /// Lists an account made.
    func lists(actor: String, cursor: String? = nil, limit: Int = 50) async throws -> ListsResponse {
        var query = ["actor": actor, "limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        return try await send("app.bsky.graph.getLists", query: query)
    }

    /// One list with its members.
    func list(uri: String, cursor: String? = nil, limit: Int = 50) async throws -> ListResponse {
        var query = ["list": uri, "limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        return try await send("app.bsky.graph.getList", query: query)
    }

    /// Lists the account blocks wholesale.
    func listBlocks(cursor: String? = nil, limit: Int = 50) async throws -> ListsResponse {
        var query = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        return try await send("app.bsky.graph.getListBlocks", query: query)
    }

    func muteList(uri: String) async throws {
        struct Body: Encodable { let list: String }
        try await sendVoid("app.bsky.graph.muteActorList", method: .post, body: Body(list: uri))
    }

    func unmuteList(uri: String) async throws {
        struct Body: Encodable { let list: String }
        try await sendVoid("app.bsky.graph.unmuteActorList", method: .post, body: Body(list: uri))
    }

    /// Blocking a list is a record, the same way blocking a person is.
    @discardableResult
    func blockList(uri: String) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.graph.listblock"
            let subject: String
            let createdAt: String
            enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }
        }
        return try await createRecord(collection: "app.bsky.graph.listblock",
                                      record: Record(subject: uri, createdAt: Self.timestamp()))
    }

    @discardableResult
    func createList(name: String, purpose: String = "app.bsky.graph.defs#modlist",
                    description: String? = nil) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.graph.list"
            let purpose: String
            let name: String
            let description: String?
            let createdAt: String
            enum CodingKeys: String, CodingKey {
                case type = "$type", purpose, name, description, createdAt
            }
        }
        return try await createRecord(
            collection: "app.bsky.graph.list",
            record: Record(purpose: purpose, name: name, description: description,
                           createdAt: Self.timestamp()))
    }

    @discardableResult
    func addToList(_ list: String, did: String) async throws -> CreateRecordResponse {
        struct Record: Encodable {
            let type = "app.bsky.graph.listitem"
            let subject: String
            let list: String
            let createdAt: String
            enum CodingKeys: String, CodingKey { case type = "$type", subject, list, createdAt }
        }
        return try await createRecord(
            collection: "app.bsky.graph.listitem",
            record: Record(subject: did, list: list, createdAt: Self.timestamp()))
    }

    // MARK: - Preferences

    func preferences() async throws -> Preferences {
        struct Response: Decodable { let preferences: [JSONValue] }
        let response: Response = try await send("app.bsky.actor.getPreferences")
        return Preferences(entries: response.preferences)
    }

    /// Writes the array back whole — including every entry Relays does not model.
    func putPreferences(_ preferences: Preferences) async throws {
        struct Body: Encodable { let preferences: [JSONValue] }
        try await sendVoid("app.bsky.actor.putPreferences", method: .post,
                           body: Body(preferences: preferences.entries))
    }

    func mute(did: String) async throws {
        struct Body: Encodable { let actor: String }
        try await sendVoid("app.bsky.graph.muteActor", method: .post, body: Body(actor: did))
    }

    func unmute(did: String) async throws {
        struct Body: Encodable { let actor: String }
        try await sendVoid("app.bsky.graph.unmuteActor", method: .post, body: Body(actor: did))
    }

    /// Deletes one of the user's own records by AT URI (a like, for instance).
    func deleteRecord(uri: String) async throws {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        let parts = uri.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw ATProtoError.invalidURL }
        let rkey = parts[parts.count - 1]
        let collection = parts[parts.count - 2]

        struct Body: Encodable { let repo: String; let collection: String; let rkey: String }
        try await sendVoid("com.atproto.repo.deleteRecord", method: .post,
                           body: Body(repo: did, collection: collection, rkey: rkey))
    }

    private struct SubjectRecord: Encodable {
        let type: String
        let subject: StrongRef
        let createdAt: String
        enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }
    }

    private struct CreateRecordBody<R: Encodable>: Encodable {
        let repo: String
        let collection: String
        let record: R
    }

    private func createRecord<R: Encodable>(collection: String, record: R) async throws -> CreateRecordResponse {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        return try await send("com.atproto.repo.createRecord", method: .post,
                              body: CreateRecordBody(repo: did, collection: collection, record: record))
    }

    // MARK: - Reply and quote rules


    /// Writes the rules for one post. `everybody` deletes the record instead of
    /// writing an empty one — no record is what "everybody" means.
    func setReplyRules(_ gate: ThreadGate, forPost uri: String) async throws {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        let rkey = Self.rkey(of: uri)

        if gate.allowsEverybody, gate.hiddenReplies.isEmpty {
            try? await deleteRecord(uri: "at://\(did)/app.bsky.feed.threadgate/\(rkey)")
            return
        }

        var record: [String: JSONValue] = [
            "$type": .string("app.bsky.feed.threadgate"),
            "post": .string(uri),
            "createdAt": .string(Self.timestamp()),
        ]
        // Nobody is an empty list; everybody-with-hidden-replies writes no list.
        if gate.allowsNobody {
            record["allow"] = .array([])
        } else if !gate.allowsEverybody {
            record["allow"] = .array(gate.rules.compactMap(\.encoded))
        }
        if !gate.hiddenReplies.isEmpty {
            record["hiddenReplies"] = .array(gate.hiddenReplies.map { .string($0) })
        }

        try await putRecord(collection: "app.bsky.feed.threadgate", rkey: rkey,
                            record: JSONValue.object(record))
    }

    /// Whether the post may be quoted, and which quotes have been detached.
    func setQuoteRules(allowed: Bool, detached: [String] = [],
                       forPost uri: String) async throws {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        let rkey = Self.rkey(of: uri)

        if allowed, detached.isEmpty {
            try? await deleteRecord(uri: "at://\(did)/app.bsky.feed.postgate/\(rkey)")
            return
        }

        let record: [String: JSONValue] = [
            "$type": .string("app.bsky.feed.postgate"),
            "post": .string(uri),
            "createdAt": .string(Self.timestamp()),
            "embeddingRules": .array(allowed ? [] :
                [.object(["$type": .string("app.bsky.feed.postgate#disableRule")])]),
            "detachedEmbeddingUris": .array(detached.map { .string($0) }),
        ]
        try await putRecord(collection: "app.bsky.feed.postgate", rkey: rkey,
                            record: JSONValue.object(record))
    }

    /// Reads back what a post's rules currently are, for editing them.
    func replyRules(forPost uri: String) async throws -> ThreadGate {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        struct Response: Decodable { let value: JSONValue }
        let response: Response = try await send(
            "com.atproto.repo.getRecord",
            query: ["repo": did, "collection": "app.bsky.feed.threadgate",
                    "rkey": Self.rkey(of: uri)])
        return Self.gate(from: response.value)
    }

    static func gate(from value: JSONValue) -> ThreadGate {
        var gate = ThreadGate()
        guard let object = value.objectValue else { return gate }

        if case .array(let allow)? = object["allow"] {
            gate.rules = allow.isEmpty ? [] : allow.compactMap(ReplyRule.init(decoded:))
        }
        if case .array(let hidden)? = object["hiddenReplies"] {
            gate.hiddenReplies = hidden.compactMap(\.stringValue)
        }
        return gate
    }

    /// Creates the record or replaces the one already at that key.
    func putRecord(collection: String, rkey: String, record: JSONValue) async throws {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        struct Body: Encodable {
            let repo: String
            let collection: String
            let rkey: String
            let record: JSONValue
        }
        try await sendVoid("com.atproto.repo.putRecord", method: .post,
                           body: Body(repo: did, collection: collection, rkey: rkey,
                                      record: record))
    }

    static func rkey(of uri: String) -> String {
        uri.split(separator: "/").last.map(String.init) ?? ""
    }

    // MARK: - Repository

    /// Downloads the account's whole repository as a CAR file. Returns the local URL.
    func exportRepo(did: String, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard var components = URLComponents(string: "\(service)/xrpc/com.atproto.sync.getRepo") else {
            throw ATProtoError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "did", value: did)]
        guard let url = components.url else { throw ATProtoError.invalidURL }

        var request = URLRequest(url: url)
        if let token = session?.accessJwt {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let destination = directory.appendingPathComponent("relays-repo-\(Self.fileStamp()).car")
        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ATProtoError.server(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                      error: nil, message: nil)
        }

        let expected = http.expectedContentLength
        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 1 << 20)

        for try await byte in bytes {
            data.append(byte)
            if expected > 0, data.count % 65_536 == 0 {
                progress(min(1, Double(data.count) / Double(expected)))
            }
        }
        progress(1)

        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Counts records in one collection, walking pages up to a ceiling.
    /// Walks a collection page by page. The ceiling stops a runaway walk over a
    /// very large repository; 10 000 records are about a hundred requests.
    func countRecords(did: String, collection: String, ceiling: Int = 10_000) async throws -> (count: Int, reachedCeiling: Bool) {
        struct Response: Decodable {
            struct Record: Decodable { let uri: String }
            let records: [Record]
            let cursor: String?
        }

        var total = 0
        var cursor: String?
        repeat {
            let page: Response = try await send("com.atproto.repo.listRecords", query: [
                "repo": did,
                "collection": collection,
                "limit": "100",
                "cursor": cursor
            ])
            total += page.records.count
            cursor = page.cursor
            if page.records.isEmpty { break }
            if total >= ceiling { return (total, true) }
        } while cursor != nil

        return (total, false)
    }

    /// The collections this repository actually holds.
    func describeRepo(did: String) async throws -> [String] {
        struct Response: Decodable { let collections: [String] }
        let response: Response = try await send("com.atproto.repo.describeRepo", query: ["repo": did])
        return response.collections
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        // A file name, not a reading: fixed format, and fixed calendar with it —
        // a device on a non-Gregorian calendar would otherwise stamp its own year.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }

    // MARK: - Transport

    private enum Method: String { case get = "GET", post = "POST" }

    private func send<T: Decodable>(
        _ endpoint: String,
        method: Method = .get,
        query: [String: String?] = [:],
        repeatedQuery: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        bearer: String? = nil
    ) async throws -> T {
        let data = try await perform(endpoint, method: method, query: query, repeatedQuery: repeatedQuery,
                                     body: body, authenticated: authenticated, bearer: bearer)
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ATProtoError.decoding(error)
        }
    }

    private func sendVoid(
        _ endpoint: String,
        method: Method = .get,
        query: [String: String?] = [:],
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        bearer: String? = nil,
        proxy: String? = nil
    ) async throws {
        _ = try await perform(endpoint, method: method, query: query, body: body,
                              authenticated: authenticated, bearer: bearer, proxy: proxy)
    }

    private func perform(
        _ endpoint: String,
        method: Method,
        query: [String: String?],
        repeatedQuery: [URLQueryItem] = [],
        body: (any Encodable)?,
        authenticated: Bool,
        bearer: String?,
        proxy: String? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(string: "\(service)/xrpc/\(endpoint)") else {
            throw ATProtoError.invalidURL
        }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        let allItems = items.sorted { $0.name < $1.name } + repeatedQuery
        if !allItems.isEmpty { components.queryItems = allItems }
        guard let url = components.url else { throw ATProtoError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        } else if method == .post {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Sends the call on to another service in the network — a labeler, when a
        // report is addressed to one — instead of the server's own default.
        if let proxy {
            request.setValue(proxy, forHTTPHeaderField: "atproto-proxy")
        }

        // The appview only returns labels from services the caller asks for. The
        // answer names the ones it actually applied — two of them cannot be
        // declined, so what comes back is not always what was asked for.
        if !acceptedLabelers.isEmpty, method == .get {
            request.setValue(acceptedLabelers.joined(separator: ", "),
                             forHTTPHeaderField: "atproto-accept-labelers")
        }

        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        } else if authenticated {
            guard let token = session?.accessJwt else { throw ATProtoError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            // A request that never left the device is not the server's fault.
            let code = (error as? URLError)?.code
            if code == .notConnectedToInternet || code == .networkConnectionLost
                || code == .dataNotAllowed {
                throw ATProtoError.offline
            }
            throw ATProtoError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }

        // "did:plc:a;redact, did:plc:b" — the flag marks one that is applied
        // whether or not it was asked for.
        if let applied = http.value(forHTTPHeaderField: "atproto-content-labelers") {
            appliedLabelers = applied
                .split(separator: ",")
                .map { $0.split(separator: ";").first.map(String.init) ?? String($0) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("did:") }
        }

        // A rate limit is not a failure, it is a "later". The server names the
        // moment; waiting once is far better than surfacing an error.
        if http.statusCode == 429, !isRetry {
            let stated = Self.retryDelay(from: http)
            // A limit with no usable delay still deserves one retry after a beat;
            // one that asks for longer than half a minute is passed to the caller.
            if stated <= 30 {
                try? await Task.sleep(for: .seconds(max(0.5, stated)))
                return try await perform(endpoint, method: method, query: query,
                                         repeatedQuery: repeatedQuery, body: body,
                                         authenticated: authenticated, bearer: bearer,
                                         proxy: proxy, isRetry: true)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(ErrorPayload.self, from: data)

            // Expired access token: refresh once and replay the original call.
            let expired = payload?.error == "ExpiredToken" || payload?.error == "InvalidToken"
            if expired, authenticated, bearer == nil, !isRetry, session?.refreshJwt != nil {
                do {
                    _ = try await refreshSession()
                } catch {
                    // A revoked app password cannot be refreshed either. Retrying
                    // will never work, so say what happened and let go of the
                    // session rather than offering "try again" forever.
                    session = nil
                    onSessionChange?(nil)
                    throw ATProtoError.sessionExpired
                }
                return try await perform(endpoint, method: method, query: query, repeatedQuery: repeatedQuery,
                                         body: body, authenticated: authenticated, bearer: bearer,
                                         proxy: proxy, isRetry: true)
            }
            if expired, authenticated, bearer == nil {
                session = nil
                onSessionChange?(nil)
                throw ATProtoError.sessionExpired
            }
            throw ATProtoError.server(status: http.statusCode, error: payload?.error, message: payload?.message)
        }
        return data
    }

    /// `retry-after` is either a number of seconds or an absolute reset time;
    /// both forms appear in the wild.
    static func retryDelay(from response: HTTPURLResponse, now: Date = Date()) -> Double {
        if let value = response.value(forHTTPHeaderField: "retry-after"),
           let seconds = Double(value.trimmingCharacters(in: .whitespaces)) {
            return max(0, seconds)
        }
        if let value = response.value(forHTTPHeaderField: "ratelimit-reset"),
           let epoch = Double(value.trimmingCharacters(in: .whitespaces)) {
            return max(0, epoch - now.timeIntervalSince1970)
        }
        return 0
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let message: String?
    }

    struct EmptyResponse: Codable {}

    private struct AnyEncodable: Encodable {
        let wrapped: any Encodable
        init(_ wrapped: any Encodable) { self.wrapped = wrapped }
        func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
