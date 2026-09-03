//
//  TimelineView.swift
//  Relays
//

import SwiftUI
import Observation

@MainActor
@Observable
final class FeedModel {
    enum Source: Equatable, Hashable {
        case timeline
        case author(String, filter: String?)
        case custom(String)
        case list(String)
        /// A hashtag, or any free-text search over posts.
        case search(String)
    }

    private(set) var posts: [FeedViewPost] = []
    private(set) var isLoading = false
    private(set) var isPaging = false
    private(set) var errorMessage: String?

    private var cursor: String?
    private var reachedEnd = false
    private let source: Source
    private let cacheID: String?

    /// A model already holding posts, for rendering previews without a network.
    static func preview(posts: [FeedViewPost]) -> FeedModel {
        let model = FeedModel(source: .timeline)
        model.seed(posts)
        return model
    }

    private func seed(_ posts: [FeedViewPost]) {
        self.posts = posts
        self.isLoading = false
    }

    init(source: Source, cacheID: String? = nil) {
        self.source = source
        self.cacheID = cacheID
    }

    func loadInitial(app: AppModel) async {
        guard posts.isEmpty, !isLoading else { return }
        // Show yesterday's page immediately, then replace it with today's.
        if let cacheID, let did = app.session?.did {
            let cached = FeedCache.load(id: cacheID, did: did)
            if !cached.isEmpty {
                posts = cached
                app.register(cached.map(\.post))
            }
        }
        await reload(app: app)
    }

    func reload(app: AppModel) async {
        isLoading = posts.isEmpty
        errorMessage = nil
        do {
            let response = try await fetch(app: app, cursor: nil)
            posts = response.feed
            cursor = response.cursor
            reachedEnd = response.cursor == nil
            app.register(response.feed.map(\.post))
            // Subscribed labelers are asked about this page directly; without a
            // subscription this returns before it does anything.
            await app.fillLabels(for: response.feed.map(\.post))
            if let cacheID, let did = app.session?.did {
                FeedCache.store(response.feed, id: cacheID, did: did)
            }
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(app: AppModel) async {
        guard !isPaging, !reachedEnd, cursor != nil else { return }
        isPaging = true
        defer { isPaging = false }

        // Strict filters can swallow a whole page. Fetch again — up to a few times —
        // rather than handing the list a page that renders as nothing.
        var rounds = 0
        while rounds < 4, !reachedEnd, let current = cursor {
            rounds += 1
            do {
                let response = try await fetch(app: app, cursor: current)
                let known = Set(posts.map(\.id))
                let fresh = response.feed.filter { !known.contains($0.id) }
                posts.append(contentsOf: fresh)
                cursor = response.cursor
                reachedEnd = response.cursor == nil || response.feed.isEmpty
                app.register(response.feed.map(\.post))

                // Something new made it through the filters: stop here.
                if fresh.contains(where: { visible($0, app: app) }) { break }
            } catch {
                reachedEnd = true
            }
        }
    }

    /// Mirrors what the list shows, so paging knows whether it achieved anything.
    private func visible(_ item: FeedViewPost, app: AppModel) -> Bool {
        guard !app.isHidden(item.post.author.did) else { return false }
        guard !app.deletedPosts.contains(item.post.uri) else { return false }
        guard !app.decision(for: item.post).hides else { return false }
        return app.rules.allows(item, origin: app.directory.origin(for: item.post.author.did))
    }

    private func fetch(app: AppModel, cursor: String?) async throws -> FeedResponse {
        switch source {
        case .timeline:
            return try await app.client.timeline(cursor: cursor)
        case .author(let actor, let filter):
            return try await app.client.authorFeed(actor: actor, filter: filter, cursor: cursor)
        case .custom(let uri):
            return try await app.client.customFeed(uri: uri, cursor: cursor)
        case .list(let uri):
            return try await app.client.listFeed(uri: uri, cursor: cursor)
        case .search(let term):
            return try await app.client.searchPosts(term: term, cursor: cursor)
        }
    }
}

struct TimelineView: View {
    var onCompose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(\.navigate) private var navigate

    @State private var catalog = FeedCatalog()
    @State private var models: [String: FeedModel] = [:]
    @State private var selection: String = FeedEntry.following.id
    @State private var showsRules = false
    @State private var showsRelay = false

    private var entry: FeedEntry {
        catalog.entries.first { $0.id == selection } ?? .following
    }

    /// Pure read. Creating the model here would write state while the view is
    /// being built, which SwiftUI rightly complains about.
    private var model: FeedModel? { models[entry.id] }

    /// Called from tasks, where mutating state is fine.
    private func ensureModel() -> FeedModel {
        if let existing = models[entry.id] { return existing }
        let created = FeedModel(source: entry.source, cacheID: entry.id)
        models[entry.id] = created
        return created
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Relays", titleAction: { showsRelay = true },
                         onRefresh: { await ensureModel().reload(app: app) }) {
                HStack(spacing: 20) {
                    Button { showsRules = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.Palette.textPrimary)
                            if app.rules.activeCount > 0 {
                                Circle()
                                    .fill(Theme.Palette.accent)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L(.settingsRules))
                }
            }
            // The hairline under the header is the firehose: same one point,
            // same place, brighter where the network wrote more.
            .overlay(alignment: .bottom) {
                if settings.relayPulse { RelayPulseLine() }
            }

            OfflineNotice()
                .animation(.easeOut(duration: 0.2), value: reachability.isOnline)

            feedPicker
            Hairline()

            content
        }
        .relaysBackground()
        .sheet(isPresented: $showsRules) {
            RulesView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsRelay) {
            RelayView()
                .presentationBackground(Theme.Palette.background)
        }
        .task {
            await catalog.load(app: app)
            await ensureModel().loadInitial(app: app)
        }
        .onChange(of: selection) { _, _ in
            let target = ensureModel()
            Task { await target.loadInitial(app: app) }
        }
        .onAppear {
            guard settings.autoRefresh, let target = model, !target.posts.isEmpty else { return }
            Task { await target.reload(app: app) }
        }
        // Back on the network: fetch once, rather than leaving the reader with
        // whatever was on screen when the connection dropped.
        .onChange(of: reachability.restoredAt) { _, _ in
            guard let target = model else { return }
            Task { await target.reload(app: app) }
        }
        // Tapping Feed while already on it: the list goes to the top and asks
        // for what has arrived since.
        .onChange(of: app.reselects[.timeline] ?? 0) { _, _ in
            guard let target = model else { return }
            Task { await target.reload(app: app) }
        }
    }

    /// Saved feeds as a single scrolling row — the timeline is always first.
    private var feedPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(catalog.entries) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = item.id }
                    } label: {
                        Text(item.title)
                            .font(Theme.Font.ui(10))
                            .tracking(0.6)
                            .lineLimit(1)
                            .foregroundStyle(selection == item.id ? Theme.Palette.background : Theme.Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selection == item.id ? Theme.Palette.accent : Theme.Palette.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 9)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var content: some View {
        if let feed = model {
            loaded(feed)
        } else {
            LoadingList()
        }
    }

    @ViewBuilder
    private func loaded(_ feed: FeedModel) -> some View {
        if feed.isLoading {
            LoadingList()
        } else if let error = feed.errorMessage, feed.posts.isEmpty {
            StateMessage(text: error, systemImage: "antenna.radiowaves.left.and.right.slash") {
                Task { await feed.reload(app: app) }
            }
            Spacer()
        } else if feed.posts.isEmpty {
            StateMessage(text: L(.feedEmpty), systemImage: "square.stack")
            Spacer()
        } else {
            FeedList(posts: feed.posts,
                     isPaging: feed.isPaging,
                     onReachEnd: { Task { await feed.loadMore(app: app) } },
                     onRefresh: { await feed.reload(app: app) },
                     scrollToTop: app.reselects[.timeline] ?? 0)
        }
    }
}

/// Shared feed list for the timeline and profile screens.
struct FeedList: View {
    let posts: [FeedViewPost]
    var isPaging: Bool
    var onReachEnd: () -> Void
    var onRefresh: () async -> Void
    /// Rises when the list should return to the top.
    var scrollToTop: Int = 0

    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var app

    private var visiblePosts: [FeedViewPost] {
        FeedVisibility.visible(posts, app: app, settings: settings)
    }

    var body: some View {
        ScrollViewReader { proxy in
            scroller
                .onChange(of: scrollToTop) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    }
                }
        }
    }

    /// A zero-height marker above the first post. Scrolling to the first post
    /// would stop just below the header on a list that has one.
    private static let topAnchor = "feed-top"

    private var scroller: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: 0).id(Self.topAnchor)
                ForEach(visiblePosts) { item in
                    FeedRow(item: item)
                    Hairline()
                        .onAppear {
                            if item.id == visiblePosts.last?.id { onReachEnd() }
                        }
                }

                if isPaging {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Palette.textTertiary)
                        .padding(.vertical, 20)
                }
            }
        }
        .scrollIndicators(.never)
        .refreshable { await onRefresh() }
    }

}

/// Placeholder shown during the first load.
struct LoadingList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Palette.surface)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.surface)
                            .frame(width: 120, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.surface)
                            .frame(maxWidth: .infinity).frame(height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.surface)
                            .frame(width: 180, height: 9)
                    }
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 14)
                .opacity(1.0 - Double(index) * 0.14)
                Hairline()
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
    }
}
