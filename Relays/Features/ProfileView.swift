//
//  ProfileView.swift
//  Relays
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ProfileModel {
    private(set) var profile: ActorProfile?
    private(set) var errorMessage: String?
    var feed: FeedModel?
    private var section: ProfileSection = .posts

    /// Each section is its own feed; switching replaces it rather than filtering
    /// what was already fetched, because the server does the filtering.
    func switchSection(_ section: ProfileSection, actor: String, app: AppModel) async {
        guard section != self.section, let did = profile?.did ?? (actor.hasPrefix("did:") ? actor : nil)
        else { return }
        self.section = section
        let created = FeedModel(source: .author(did, filter: section.filter))
        feed = created
        await created.reload(app: app)
    }

    /// Fills the model without touching the network, for rendering previews.
    static func preview(profile: ActorProfile, posts: [FeedViewPost]) -> ProfileModel {
        let model = ProfileModel()
        model.apply(profile: profile, posts: posts)
        return model
    }

    private func apply(profile: ActorProfile, posts: [FeedViewPost]) {
        self.profile = profile
        self.feed = FeedModel.preview(posts: posts)
    }

    /// Pull-to-refresh: the profile itself and the section currently shown.
    func refresh(actor: String, app: AppModel) async {
        async let profileReload: Void = reloadProfile(actor: actor, app: app)
        async let feedReload: Void = feed?.reload(app: app) ?? ()
        _ = await (profileReload, feedReload)
    }

    private func reloadProfile(actor: String, app: AppModel) async {
        guard let loaded = try? await app.client.profile(actor: actor) else { return }
        profile = loaded
        app.register(moderationOf: loaded)
    }

    func load(actor: String, app: AppModel) async {
        do {
            let loaded = try await app.client.profile(actor: actor)
            profile = loaded
            app.register(moderationOf: loaded)
            if feed == nil {
                let created = FeedModel(source: .author(loaded.did, filter: section.filter))
                feed = created
                await created.reload(app: app)
            }
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ProfileView: View {
    let actor: String
    var isRoot: Bool = false

    /// A zero-height marker above the banner, so returning to the top lands
    /// above the header rather than at the first post.
    private static let topAnchor = "profile-top"

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose

    @State private var model: ProfileModel
    @State private var showsEditor = false
    @State private var showsSettings = false

    /// `model` is supplied only when rendering previews; the app lets the view
    /// create its own and load it from the network.
    @MainActor
    init(actor: String, isRoot: Bool = false, model: ProfileModel? = nil) {
        self.actor = actor
        self.isRoot = isRoot
        self._model = State(initialValue: model ?? ProfileModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: isRoot ? L(.tabProfile) : (model.profile?.handle ?? L(.tabProfile)),
                         showsBack: !isRoot,
                         onRefresh: { await model.refresh(actor: actor, app: app) }) {
                if isRoot {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L(.a11ySettings))
                    .accessibilityLabel(L(.titleSettings))
                }
            }

            if let error = model.errorMessage, model.profile == nil {
                StateMessage(text: error, systemImage: "person.slash") {
                    Task { await model.load(actor: actor, app: app) }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                  ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 0).id(Self.topAnchor)
                        ProfileHeader(profile: model.profile,
                                      actor: actor,
                                      isRoot: isRoot,
                                      onOpenList: { kind in
                                          navigate(.actorList(subject: model.profile?.did ?? actor, kind: kind))
                                      },
                                      onEdit: { showsEditor = true })

                        sectionPicker
                        Hairline()

                        if let feed = model.feed {
                            let visible = FeedVisibility.visible(feed.posts, app: app, settings: settings)
                            ForEach(visible) { item in
                                FeedRow(item: item)
                                Hairline()
                                    .onAppear {
                                        if item.id == visible.last?.id {
                                            Task { await feed.loadMore(app: app) }
                                        }
                                    }
                            }
                            if visible.isEmpty && !feed.isLoading {
                                StateMessage(text: L(.profileEmpty))
                            }
                        } else {
                            LoadingList()
                        }
                    }
                  }
                  .scrollIndicators(.never)
                  .refreshable { await model.refresh(actor: actor, app: app) }
                  // Tapping Profile while already on it, and only on one's own
                  // profile — the tab bar has no meaning on somebody else's.
                  .onChange(of: isRoot ? (app.reselects[.profile] ?? 0) : 0) { _, _ in
                      withAnimation(.easeOut(duration: 0.25)) {
                          proxy.scrollTo(Self.topAnchor, anchor: .top)
                      }
                      Task { await model.refresh(actor: actor, app: app) }
                  }
                }
            }
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task { await model.load(actor: actor, app: app) }
        // The menu offers the reader's own lists, so they have to be known.
        .task { if app.ownLists.isEmpty { await app.loadLists() } }
        .sheet(isPresented: $showsEditor) {
            EditProfileView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsScreen()
                .presentationBackground(Theme.Palette.background)
        }
        .onChange(of: app.profileSection) { _, section in
            Task { await model.switchSection(section, actor: actor, app: app) }
        }
    }

    /// Own profile splits into posts and options instead of a separate settings screen.
    private var sectionPicker: some View {
        @Bindable var app = app

        return HStack(spacing: 6) {
            ForEach(ProfileSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { app.profileSection = section }
                } label: {
                    Text(section.label)
                        .font(Theme.Font.ui(14, .medium))
                        .foregroundStyle(app.profileSection == section ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(app.profileSection == section ? Theme.Palette.accent : Theme.Palette.surface)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.bottom, 14)
    }

}


/// Banner, overlapping avatar, name, bio and counts — the arrangement that makes
/// a profile read as a profile in this family of apps.
struct ProfileHeader: View {
    let profile: ActorProfile?
    let actor: String
    var isRoot: Bool = false
    var onOpenList: (ActorListKind) -> Void = { _ in }
    var onEdit: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var app
    @Environment(\.report) private var report

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if settings.showImages, let bannerURL = profile?.bannerURL {
                        AsyncImage(url: bannerURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Theme.Palette.surface
                            }
                        }
                    } else {
                        Theme.Palette.surface
                    }
                }
                .frame(height: 124)
                .frame(maxWidth: .infinity)
                .clipped()

                AvatarView(url: profile?.avatarURL, seed: profile?.handle ?? actor, size: 76)
                    .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 4))
                    .padding(.leading, Theme.Metric.hPadding)
                    .offset(y: 38)
            }
            .padding(.bottom, 38)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(profile?.name ?? "…")
                            .font(Theme.Font.ui(20, .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        VerificationBadge(verification: profile?.verification, size: 17)
                    }
                    Text("@\(profile?.handle ?? "")")
                        .font(Theme.Font.ui(15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isRoot {
                    Button { onEdit() } label: {
                        Text(L(.editProfile))
                            .font(Theme.Font.ui(15, .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if let profile, !isRoot {
                    HStack(spacing: 10) {
                        Menu {
                            Button {
                                report(ReportTarget(kind: .account(profile)))
                            } label: {
                                Label(L(.moderationReport), systemImage: "flag")
                            }
                            Button {
                                Task { await app.toggleMute(profile) }
                            } label: {
                                Label(app.isMuted(profile.did) ? L(.moderationUnmute) : L(.moderationMute),
                                      systemImage: app.isMuted(profile.did) ? "speaker.wave.2" : "speaker.slash")
                            }
                            // A list is how one decision covers many accounts.
                            Menu {
                                if app.ownLists.filter(\.isModeration).isEmpty {
                                    Text(L(.listNone))
                                }
                                ForEach(app.ownLists.filter(\.isModeration)) { list in
                                    Button(list.name) {
                                        Task { await app.addToList(list, profile: profile) }
                                    }
                                }
                            } label: {
                                Label(L(.listAddTo), systemImage: "text.badge.plus")
                            }
                            Button(role: .destructive) {
                                Task { await app.toggleBlock(profile) }
                            } label: {
                                Label(app.isBlocked(profile.did) ? L(.moderationUnblock) : L(.moderationBlock),
                                      systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
                        }
                        .plainMenu()
                        .accessibilityLabel(L(.moderationReport))

                        FollowButton(profile: profile)
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.top, 10)

            // An account that runs a moderation service can be subscribed to
            // from here — that is where people meet one.
            if let profile, profile.isLabeler {
                HStack(spacing: 10) {
                    Label(L(.labelersIsLabeler), systemImage: "checkmark.shield")
                        .font(Theme.Font.ui(13, .medium))
                        .foregroundStyle(Theme.Palette.link)
                    Spacer(minLength: 8)
                    LabelerSubscribeButton(did: profile.did)
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.top, 10)
            }

            if let profile, app.isBlocked(profile.did) || app.isMuted(profile.did) {
                Label(app.isBlocked(profile.did) ? L(.moderationBlocked) : L(.moderationMuted),
                      systemImage: app.isBlocked(profile.did) ? "hand.raised.fill" : "speaker.slash.fill")
                    .font(Theme.Font.ui(13, .medium))
                    .foregroundStyle(Theme.Palette.danger)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.top, 10)
            }

            if let description = profile?.description, !description.isEmpty {
                RichTextView(text: description,
                             font: Theme.Font.ui(15),
                             color: Theme.Palette.textPrimary,
                             autoLink: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.top, 10)
            }

            HStack(spacing: 18) {
                stat(profile?.followsCount, L(.statFollowing)) { onOpenList(.following) }
                stat(profile?.followersCount, L(.statFollowers)) { onOpenList(.followers) }
                stat(profile?.postsCount, L(.statPosts), action: nil)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    /// Follower counts open the list behind them; the post count has none to open.
    private func stat(_ value: Int?, _ label: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 4) {
                Text(Format.compact(value ?? 0, fullBelow: 10_000))
                    .font(Theme.Font.ui(15, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(label)
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("\(value ?? 0) \(label)")
    }

}
