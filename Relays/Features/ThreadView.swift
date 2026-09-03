//
//  ThreadView.swift
//  Relays
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ThreadModel {
    private(set) var ancestors: [PostView] = []
    private(set) var post: PostView?
    private(set) var replies: [PostView] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    func load(uri: String, app: AppModel) async {
        errorMessage = nil
        do {
            let response = try await app.client.thread(uri: uri)
            ancestors = response.thread.ancestors
            post = response.thread.post
            replies = (response.thread.replies ?? []).compactMap(\.post)
            app.register(ancestors + [post].compactMap { $0 } + replies)
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct ThreadView: View {
    let uri: String

    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose

    @State private var model = ThreadModel()

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.titleThread), showsBack: true)

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage {
                StateMessage(text: error, systemImage: "exclamationmark.triangle") {
                    Task { await model.load(uri: uri, app: app) }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.ancestors) { ancestor in
                            row(ancestor)
                            Hairline()
                        }

                        if let post = model.post {
                            PostRowView(post: post,
                                        isDetail: true,
                                        onOpenProfile: { navigate(.profile(actor: $0.did)) },
                                        onReply: { compose(ComposeTarget(replyTo: $0)) },
                                        onOpenQuotes: { navigate(.quotes(uri: $0.uri)) },
                                        onOpenActors: { navigate(.actorList(subject: $0.uri, kind: $1)) })
                            .background(Theme.Palette.surface.opacity(0.35))
                            Hairline()
                        }

                        ForEach(model.replies) { reply in
                            // A thread with a blocked account in the middle must
                            // not fall apart; the gap is part of the thread.
                            let decision = app.decision(for: reply)
                            let foldedAway = model.post.map {
                                app.gate(for: $0).hiddenReplies.contains(reply.uri)
                            } ?? false

                            if decision.hides {
                                ModerationGap(reason: decision.reason)
                                    .padding(.leading, 8)
                            } else if foldedAway, let root = model.post {
                                // The author put it away. They can still take it
                                // back out, so the gap keeps the menu.
                                ModerationGap(reason: L(.replyHidden))
                                    .padding(.leading, 8)
                                    .contextMenu {
                                        Button {
                                            Task {
                                                await app.toggleHiddenReply(reply, inThreadOf: root)
                                            }
                                        } label: {
                                            Label(L(.unhideReply), systemImage: "eye")
                                        }
                                    }
                            } else {
                                row(reply, root: model.post)
                                    .padding(.leading, 8)
                            }
                            Hairline(inset: 8)
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
        .task { await model.load(uri: uri, app: app) }
    }

    private func row(_ post: PostView, root: PostView? = nil) -> some View {
        PostRowView(post: post,
                    onOpenThread: { navigate(.thread(uri: $0.uri)) },
                    onOpenProfile: { navigate(.profile(actor: $0.did)) },
                    onReply: { compose(ComposeTarget(replyTo: $0)) },
                    onOpenQuotes: { navigate(.quotes(uri: $0.uri)) },
                    onOpenActors: { navigate(.actorList(subject: $0.uri, kind: $1)) },
                    threadRoot: root)
    }
}

/// The place a hidden reply held. Saying nothing here would make a thread read
/// as though the conversation had jumped.
struct ModerationGap: View {
    let reason: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.system(size: 11))
            Text(reason ?? L(.moderationCovered))
                .font(Theme.Font.ui(13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Palette.textTertiary)
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 12)
    }
}
