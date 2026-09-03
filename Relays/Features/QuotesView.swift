//
//  QuotesView.swift
//  Relays
//
//  Who quoted a post. The count sits on the repost control; this is what is
//  behind it — until now the number was the end of the road.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class QuotesModel {
    private(set) var posts: [FeedViewPost] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private var cursor: String?
    private var reachedEnd = false

    /// Already filled, for rendering without a network.
    static func preview(_ posts: [FeedViewPost]) -> QuotesModel {
        let model = QuotesModel()
        model.posts = posts
        model.isLoading = false
        return model
    }

    func load(uri: String, app: AppModel) async {
        guard posts.isEmpty else { return }
        errorMessage = nil
        do {
            let response = try await app.client.quotes(of: uri)
            posts = response.feed
            cursor = response.cursor
            reachedEnd = response.cursor == nil
            app.register(response.feed.map(\.post))
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(uri: String, app: AppModel) async {
        guard !reachedEnd, let cursor else { return }
        guard let response = try? await app.client.quotes(of: uri, cursor: cursor) else { return }
        posts += response.feed
        self.cursor = response.cursor
        reachedEnd = response.cursor == nil
        app.register(response.feed.map(\.post))
    }
}

struct QuotesView: View {
    let uri: String

    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose

    @State private var model = QuotesModel()

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.quotesTitle), showsBack: true)
            OfflineNotice()

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, model.posts.isEmpty {
                StateMessage(text: error, systemImage: "quote.opening") {
                    Task { await model.load(uri: uri, app: app) }
                }
                Spacer()
            } else if model.posts.isEmpty {
                StateMessage(text: L(.quotesEmpty), systemImage: "quote.opening")
                Spacer()
            } else {
                FeedList(posts: model.posts,
                         isPaging: false,
                         onReachEnd: { Task { await model.loadMore(uri: uri, app: app) } },
                         onRefresh: { await model.load(uri: uri, app: app) })
            }
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task { await model.load(uri: uri, app: app) }
    }
}
