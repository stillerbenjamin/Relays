//
//  HomeView.swift
//  Relays
//

import SwiftUI

enum Route: Hashable {
    case thread(uri: String)
    case profile(actor: String)
    case actorList(subject: String, kind: ActorListKind)
    case hashtag(String)
    case conversation(id: String)
    case quotes(uri: String)
}

/// What a tap on the bar means. Pulled out of the button so the rule can be
/// checked without a signed-in account and a finger.
enum TabTap {
    enum Outcome: Equatable {
        case switchTo(Tab)
        /// Something is pushed on top: that goes away first.
        case popToRoot
        /// Already at the root of the tab that is showing: to the top, and fetch.
        case backToTop
    }

    static func outcome(tapped: Tab, current: Tab, isPushed: Bool) -> Outcome {
        guard tapped == current else { return .switchTo(tapped) }
        return isPushed ? .popToRoot : .backToTop
    }
}

/// Five destinations. Options live inside the profile — the bar carries only
/// what people switch between, not everything the app can do.
enum Tab: String, CaseIterable, Identifiable {
    case timeline, search, messages, notifications, profile

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .timeline: return "house"
        case .search: return "magnifyingglass"
        case .messages: return "bubble.left.and.bubble.right"
        case .notifications: return "bell"
        case .profile: return "person"
        }
    }

    /// Filled variant for the active tab, as in the apps this follows.
    var activeSymbol: String {
        switch self {
        case .timeline: return "house.fill"
        case .search: return "magnifyingglass"
        case .messages: return "bubble.left.and.bubble.right"
        case .notifications: return "bell.fill"
        case .profile: return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .timeline: return L(.tabFeed)
        case .search: return L(.tabSearch)
        case .messages: return L(.tabMessages)
        case .notifications: return L(.tabNotifications)
        case .profile: return L(.tabProfile)
        }
    }
}

enum ProfileSection: String, CaseIterable, Identifiable {
    case posts, replies, media

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return L(.statPosts)
        case .replies: return L(.sectionReplies)
        case .media: return L(.sectionMedia)
        }
    }

    /// The lexicon's filter for this section.
    var filter: String {
        switch self {
        case .posts: return "posts_no_replies"
        case .replies: return "posts_with_replies"
        case .media: return "posts_with_media"
        }
    }
}

struct HomeView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AppModel.self) private var app

    @State private var paths: [Tab: [Route]] = [:]
    @State private var composeTarget: ComposeTarget?

    private var tab: Tab { app.selectedTab }

    var body: some View {
        @Bindable var app = app

        return ZStack(alignment: .bottom) {
            #if os(iOS)
            Theme.Palette.background.ignoresSafeArea()
            #else
            Theme.Palette.background
            #endif

            Group {
                switch tab {
                case .timeline:
                    stack(for: .timeline) {
                        TimelineView(onCompose: { composeTarget = ComposeTarget(replyTo: nil) })
                    }
                case .search:
                    stack(for: .search) { SearchView() }
                case .messages:
                    stack(for: .messages) { MessagesView() }
                case .notifications:
                    stack(for: .notifications) { NotificationsView() }
                case .profile:
                    stack(for: .profile) {
                        ProfileView(actor: app.session?.did ?? "", isRoot: true)
                    }
                }
            }
            .padding(.bottom, 56)

            // Posting belongs where posts live. Alerts are for reading, and
            // messages have their own way to start one.
            if tab == .timeline || tab == .profile {
                composeButton
                    .padding(.trailing, Theme.Metric.hPadding)
                    .padding(.bottom, 72)
            }

            tabBar
        }
        .readingColumn()
        .environment(\.composeAction, ComposeAction { target in composeTarget = target })
        .environment(\.navigate, NavigateAction { route in
            paths[app.selectedTab, default: []].append(route)
        })
        .sheet(item: $composeTarget) { target in
            ComposeView(target: target)
                .environment(app)
        }
    }

    @ViewBuilder
    private func stack<Content: View>(for tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: binding(for: tab)) {
            content()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .thread(let uri):
                        ThreadView(uri: uri)
                    case .profile(let actor):
                        ProfileView(actor: actor)
                    case .actorList(let subject, let kind):
                        ActorListView(subject: subject, kind: kind)
                    case .hashtag(let tag):
                        HashtagView(tag: tag)
                    case .conversation(let id):
                        ConversationView(id: id)
                    case .quotes(let uri):
                        QuotesView(uri: uri)
                    }
                }
        }
        .tint(Theme.Palette.textPrimary)
    }

    private func binding(for tab: Tab) -> Binding<[Route]> {
        Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )
    }

    /// Writing is one tap from anywhere, not buried in a header.
    private var composeButton: some View {
        HStack {
            Spacer()
            ComposeButton { composeTarget = ComposeTarget(replyTo: nil) }
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        switch TabTap.outcome(tapped: item, current: app.selectedTab,
                                              isPushed: paths[item]?.isEmpty == false) {
                        case .switchTo(let next):
                            app.selectedTab = next
                        case .popToRoot:
                            paths[item] = []
                        case .backToTop:
                            app.reselect(item)
                        }
                        if item == .notifications {
                            Task { await app.markNotificationsRead(badging: notifications) }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab == item ? item.activeSymbol : item.symbol)
                                    .font(.system(size: 20, weight: tab == item ? .semibold : .regular))
                                if item == .notifications && app.unreadNotifications > 0 {
                                    Circle()
                                        .fill(Theme.Palette.accent)
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 1.5))
                                        .offset(x: 7, y: -3)
                                }
                            }
                            Text(item.title)
                                .font(Theme.Font.tab)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(tab == item ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 9)
            .padding(.bottom, 2)
            .background(Theme.Palette.background)
        }
    }
}

// MARK: - Compose plumbing

struct ComposeTarget: Identifiable {
    let id = UUID()
    var replyTo: PostView?
    /// The post being quoted, if any.
    var quoting: PostView?
}

struct ComposeAction {
    let handler: (ComposeTarget) -> Void
    func callAsFunction(_ target: ComposeTarget) { handler(target) }
    init(_ handler: @escaping (ComposeTarget) -> Void) { self.handler = handler }
}

private struct ComposeActionKey: EnvironmentKey {
    static let defaultValue = ComposeAction { _ in }
}

extension EnvironmentValues {
    var composeAction: ComposeAction {
        get { self[ComposeActionKey.self] }
        set { self[ComposeActionKey.self] = newValue }
    }
}

// MARK: - Navigation from nested views

struct NavigateAction {
    let handler: (Route) -> Void
    func callAsFunction(_ route: Route) { handler(route) }
    init(_ handler: @escaping (Route) -> Void) { self.handler = handler }
}

private struct NavigateActionKey: EnvironmentKey {
    static let defaultValue = NavigateAction { _ in }
}

extension EnvironmentValues {
    var navigate: NavigateAction {
        get { self[NavigateActionKey.self] }
        set { self[NavigateActionKey.self] = newValue }
    }
}

/// Header in the reference style: centred monospaced title on black.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var showsBack: Bool = false
    /// Set where the screen has something behind its own name.
    var titleAction: (() -> Void)? = nil
    /// A Mac has no pull gesture, so `refreshable` is unreachable there. A
    /// screen that can be refreshed says so here and gets a button and ⌘R; on
    /// iOS the pull is the whole story and this draws nothing.
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let titleAction {
                    Button(action: titleAction) {
                        Text(title)
                            .font(Theme.Font.ui(17, .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(Theme.Font.ui(17, .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }

                HStack {
                    if showsBack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(.cancel))
                    }
                    Spacer()
                    #if os(macOS)
                    if let onRefresh {
                        refreshButton(onRefresh)
                    }
                    #endif
                    trailing
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 48)

            Hairline()
        }
        .background(Theme.Palette.background)
    }

    #if os(macOS)
    private func refreshButton(_ action: @escaping () async -> Void) -> some View {
        Button {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task {
                await action()
                isRefreshing = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isRefreshing ? Theme.Palette.textTertiary
                                              : Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(isRefreshing)
        .accessibilityLabel(L(.refresh))
        .padding(.trailing, 14)
    }
    #endif
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, showsBack: Bool = false,
         onRefresh: (() async -> Void)? = nil) {
        self.init(title: title, showsBack: showsBack, onRefresh: onRefresh,
                  trailing: { EmptyView() })
    }
}


/// The floating compose button.
///
/// `square.and.pencil` is not drawn on its own centre: the pencil overhangs the
/// box to the upper right, so centring the glyph's frame leaves it looking high
/// and left. The offset below puts its visual mass in the middle of the circle.
struct ComposeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Palette.onAccent)
                // Measured against the circle it sits in: without this, the glyph's
                // box lands about half a point right and three quarters low.
                .offset(x: -0.5, y: -0.8)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Theme.Palette.accent))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(.composePlaceholder))
    }
}
