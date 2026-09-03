//
//  ActorListView.swift
//  Relays
//
//  Who follows an account, who it follows, who liked a post and who reposted
//  it. Four lists of accounts with one shape, so the subject is sometimes an
//  account and sometimes a post — hence `subject` rather than `actor`.
//

import SwiftUI
import Observation

enum ActorListKind: String, Hashable, Codable {
    case followers, following, likes, reposts

    var title: String {
        switch self {
        case .followers: return L(.statFollowers)
        case .following: return L(.statFollowing)
        case .likes: return L(.likesTitle)
        case .reposts: return L(.repostsTitle)
        }
    }

    /// The subject is an account for two of these and a post for the other two.
    var subjectIsPost: Bool { self == .likes || self == .reposts }

    var emptyText: String {
        subjectIsPost ? L(.postListEmpty) : L(.actorListEmpty)
    }
}

@MainActor
@Observable
final class ActorListModel {
    private(set) var actors: [ActorProfile] = []
    private(set) var isLoading = true
    private(set) var isPaging = false
    private(set) var errorMessage: String?

    private var cursor: String?
    private var reachedEnd = false

    /// Discards what was loaded and fetches the first page again.
    func refresh(subject: String, kind: ActorListKind, app: AppModel) async {
        actors = []
        cursor = nil
        reachedEnd = false
        await load(subject: subject, kind: kind, app: app)
    }

    func load(subject: String, kind: ActorListKind, app: AppModel) async {
        guard actors.isEmpty else { return }
        errorMessage = nil
        do {
            let page = try await fetch(subject: subject, kind: kind, cursor: nil, app: app)
            actors = page.actors
            cursor = page.cursor
            reachedEnd = page.cursor == nil
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(subject: String, kind: ActorListKind, app: AppModel) async {
        guard !isPaging, !reachedEnd, let cursor else { return }
        isPaging = true
        do {
            let page = try await fetch(subject: subject, kind: kind, cursor: cursor, app: app)
            let known = Set(actors.map(\.did))
            actors.append(contentsOf: page.actors.filter { !known.contains($0.did) })
            self.cursor = page.cursor
            reachedEnd = page.cursor == nil || page.actors.isEmpty
        } catch {
            reachedEnd = true
        }
        isPaging = false
    }

    private func fetch(subject: String, kind: ActorListKind,
                       cursor: String?, app: AppModel) async throws -> ActorListResponse {
        switch kind {
        case .followers: return try await app.client.followers(actor: subject, cursor: cursor)
        case .following: return try await app.client.follows(actor: subject, cursor: cursor)
        case .likes: return try await app.client.likes(of: subject, cursor: cursor)
        case .reposts: return try await app.client.repostedBy(uri: subject, cursor: cursor)
        }
    }
}

struct ActorListView: View {
    /// An account for followers and following; a post's URI for likes and
    /// reposts.
    let subject: String
    let kind: ActorListKind

    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    @State private var model = ActorListModel()

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: kind.title, showsBack: true,
                         onRefresh: { await model.refresh(subject: subject, kind: kind, app: app) })

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, model.actors.isEmpty {
                StateMessage(text: error, systemImage: "person.slash") {
                    Task { await model.load(subject: subject, kind: kind, app: app) }
                }
                Spacer()
            } else if model.actors.isEmpty {
                StateMessage(text: kind.emptyText, systemImage: "person")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.actors) { profile in
                            ActorRow(profile: profile)
                                .onTapGesture { navigate(.profile(actor: profile.did)) }
                            Hairline(inset: Theme.Metric.hPadding)
                                .onAppear {
                                    if profile.did == model.actors.last?.did {
                                        Task { await model.loadMore(subject: subject, kind: kind, app: app) }
                                    }
                                }
                        }

                        if model.isPaging {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.Palette.textTertiary)
                                .padding(.vertical, 20)
                        }
                    }
                }
                .scrollIndicators(.never)
                .refreshable { await model.refresh(subject: subject, kind: kind, app: app) }
            }
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task { await model.load(subject: subject, kind: kind, app: app) }
    }
}

/// One account in a list, with its bio trimmed to a single line.
struct ActorRow: View {
    let profile: ActorProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: profile.avatarURL, seed: profile.handle, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name)
                        .font(Theme.Font.ui(13, .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    VerificationBadge(verification: profile.verification, size: 12)
                }
                Text("@\(profile.handle)")
                    .font(Theme.Font.ui(10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                if let description = profile.description?
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces), !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.ui(11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)

            FollowButton(profile: profile, compact: true)
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
