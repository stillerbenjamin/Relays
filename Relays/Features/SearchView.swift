//
//  SearchView.swift
//  Relays
//

import SwiftUI
import Observation

enum SearchScope: String, CaseIterable, Identifiable {
    case people, posts

    var id: String { rawValue }
    var label: String { self == .people ? L(.searchPeople) : L(.searchPosts) }
}

@MainActor
@Observable
final class SearchModel {
    private(set) var results: [ActorProfile] = []
    private(set) var posts: [FeedViewPost] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    /// What to show before anybody has typed anything: feeds other people keep,
    /// and accounts the network suggests. An empty screen with a hint on it is a
    /// wasted screen.
    private(set) var popularFeeds: [FeedGeneratorView] = []
    private(set) var suggestedActors: [ActorProfile] = []
    private(set) var isDiscovering = false
    private var discovered = false

    private var task: Task<Void, Never>?

    func discover(app: AppModel) async {
        guard !discovered, !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        async let feeds = try? app.client.popularFeeds(limit: 12)
        async let actors = try? app.client.suggestedActors(limit: 12)

        popularFeeds = await feeds ?? []
        suggestedActors = await actors ?? []
        for actor in suggestedActors { app.register(actor) }
        discovered = !popularFeeds.isEmpty || !suggestedActors.isEmpty
    }

    /// Debounced search so every keystroke does not fire a request.
    func search(term: String, scope: SearchScope, app: AppModel) {
        task?.cancel()
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            results = []
            posts = []
            isSearching = false
            return
        }

        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                switch scope {
                case .people:
                    let response = try await app.client.searchActors(term: query)
                    guard !Task.isCancelled else { return }
                    results = response.actors
                case .posts:
                    let response = try await app.client.searchPosts(term: query)
                    guard !Task.isCancelled else { return }
                    posts = response.feed
                    app.register(response.feed.map(\.post))
                }
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            }
            isSearching = false
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    @State private var model = SearchModel()
    @State private var term = ""
    @State private var scope: SearchScope = .people

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.tabSearch), showsBack: true)

            MonoField(icon: "magnifyingglass",
                      placeholder: L(.searchPlaceholder),
                      text: $term,
                      submitLabel: .search)
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { scope = option }
                        model.search(term: term, scope: option, app: app)
                    } label: {
                        Text(option.label)
                            .font(Theme.Font.ui(14, .medium))
                            .foregroundStyle(scope == option ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(scope == option ? Theme.Palette.accent : Theme.Palette.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.bottom, 12)

            if scope == .posts {
                postResults
            } else if model.isSearching && model.results.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Palette.textTertiary)
                    .padding(.top, 24)
                Spacer()
            } else if model.results.isEmpty {
                if term.count >= 2 {
                    StateMessage(text: L(.searchEmpty), systemImage: "magnifyingglass")
                    Spacer()
                } else {
                    DiscoverList(model: model)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { profile in
                            Button {
                                navigate(.profile(actor: profile.did))
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(url: profile.avatarURL, seed: profile.handle, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(Theme.Font.ui(13, .medium))
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                            .lineLimit(1)
                                        Text("@\(profile.handle)")
                                            .font(Theme.Font.micro)
                                            .foregroundStyle(Theme.Palette.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    FollowButton(profile: profile, compact: true)
                                }
                                .padding(.horizontal, Theme.Metric.hPadding)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hairline(inset: Theme.Metric.hPadding)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onChange(of: term) { _, new in
            model.search(term: new, scope: scope, app: app)
        }
    }
}


extension SearchView {
    /// Post results share the timeline's row, so a hit reads exactly like a post.
    @ViewBuilder
    fileprivate var postResults: some View {
        if model.isSearching && model.posts.isEmpty {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.textTertiary)
                .padding(.top, 24)
            Spacer()
        } else if model.posts.isEmpty {
            if term.count >= 2 {
                StateMessage(text: L(.searchEmpty), systemImage: "magnifyingglass")
                Spacer()
            } else {
                DiscoverList(model: model)
            }
        } else {
            FeedList(posts: model.posts,
                     isPaging: false,
                     onReachEnd: {},
                     onRefresh: { model.search(term: term, scope: .posts, app: app) })
        }
    }
}


/// What the search screen shows before anything is typed: feeds worth keeping
/// and accounts worth following. Both come from the network, not from a list
/// somebody baked into the app.
struct DiscoverList: View {
    let model: SearchModel

    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.isDiscovering && model.popularFeeds.isEmpty {
                    ProgressView().controlSize(.small).tint(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }

                if !model.popularFeeds.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        RelaySectionTitle(text: L(.discoverFeeds))
                        ForEach(model.popularFeeds) { feed in
                            DiscoverFeedRow(feed: feed)
                        }
                    }
                }

                if !model.suggestedActors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        RelaySectionTitle(text: L(.discoverPeople))
                        ForEach(model.suggestedActors) { profile in
                            Button { navigate(.profile(actor: profile.did)) } label: {
                                HStack(spacing: Theme.Metric.avatarGap) {
                                    AvatarView(url: profile.avatarURL, seed: profile.handle, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(profile.name)
                                            .font(Theme.Font.ui(15, .medium))
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                            .lineLimit(1)
                                        Text("@\(profile.handle)")
                                            .font(Theme.Font.mono(11))
                                            .foregroundStyle(Theme.Palette.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    FollowButton(profile: profile, compact: true)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !model.isDiscovering, model.popularFeeds.isEmpty, model.suggestedActors.isEmpty {
                    StateMessage(text: L(.searchHint), systemImage: "magnifyingglass")
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .task { await model.discover(app: app) }
    }
}

/// One feed, with the one thing to do about it.
struct DiscoverFeedRow: View {
    let feed: FeedGeneratorView

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Metric.avatarGap) {
            AvatarView(url: feed.avatar.flatMap(URL.init(string:)), seed: feed.uri, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.displayName)
                    .font(Theme.Font.ui(15, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                if let description = feed.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.ui(12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let likes = feed.likeCount, likes > 0 {
                    Text(L(.discoverKept, Format.compact(likes)))
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            Spacer(minLength: 8)

            let saved = app.isSaved(feed.uri)
            Button {
                Task { await app.toggleSavedFeed(feed.uri) }
            } label: {
                Text(saved ? L(.discoverRemove) : L(.discoverKeep))
                    .font(Theme.Font.ui(12, .medium))
                    .foregroundStyle(saved ? Theme.Palette.textSecondary : Theme.Palette.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(saved ? Theme.Palette.surfaceRaised
                                                     : Theme.Palette.accent))
            }
            .buttonStyle(.plain)
        }
    }
}
