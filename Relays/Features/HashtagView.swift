//
//  HashtagView.swift
//  Relays
//
//  Everything posted under one tag. Tags are not a separate index on the network —
//  they resolve to a post search — but they behave like a feed, so they read like one.
//

import SwiftUI

struct HashtagView: View {
    let tag: String

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose

    @State private var model: FeedModel?

    /// The stored form carries no '#'; the query and the title both add it back.
    private var query: String { "#\(tag)" }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: query, showsBack: true)
            content
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            let feed = ensureModel()
            await feed.loadInitial(app: app)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let feed = model {
            if feed.isLoading {
                LoadingList()
            } else if let error = feed.errorMessage, feed.posts.isEmpty {
                StateMessage(text: error, systemImage: "number") {
                    Task { await feed.reload(app: app) }
                }
                Spacer()
            } else if feed.posts.isEmpty {
                StateMessage(text: L(.hashtagEmpty, query), systemImage: "number")
                Spacer()
            } else {
                FeedList(posts: feed.posts,
                         isPaging: feed.isPaging,
                         onReachEnd: { Task { await feed.loadMore(app: app) } },
                         onRefresh: { await feed.reload(app: app) })
            }
        } else {
            LoadingList()
        }
    }

    private func ensureModel() -> FeedModel {
        if let existing = model { return existing }
        let created = FeedModel(source: .search(query))
        model = created
        return created
    }
}
