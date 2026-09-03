//
//  NotificationKindsView.swift
//  Relays
//
//  Twelve kinds, each with an audience and two switches, is thirty-two controls
//  if you draw it literally. Nobody wants that screen.
//
//  So: one audience for all eight kinds that have one, and a three-state choice
//  per kind instead of two toggles — off, in the list, alert me. The same shape
//  the label-visibility rows already use.
//

import SwiftUI

struct NotificationKindsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// How much of a notification somebody wants. `(list: false, push: true)`
    /// reads back as `.alert` — it still alerts, whatever else it is.
    enum Level: String, CaseIterable, Identifiable, Hashable {
        case off, list, alert

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: return L(.notifyOff)
            case .list: return L(.notifyListOnly)
            case .alert: return L(.notifyAlert)
            }
        }

        static func of(_ setting: NotificationPreferences.Setting) -> Level {
            if setting.push { return .alert }
            return setting.list ? .list : .off
        }

        var applied: (list: Bool, push: Bool) {
            switch self {
            case .off: return (false, false)
            case .list: return (true, false)
            case .alert: return (true, true)
            }
        }
    }

    /// `Mixed` is offered only while the account actually is mixed — another
    /// client can set the eight audiences one at a time. Showing it is telling
    /// the truth; picking something else is what resolves it.
    private enum AudienceChoice: String, CaseIterable, Identifiable, Hashable {
        case all, follows, mixed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return L(.notifyAudienceAll)
            case .follows: return L(.notifyAudienceFollows)
            case .mixed: return L(.notifyAudienceMixed)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.notifyKinds)) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L(.notifyKindsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    audience

                    group(L(.notifyGroupPosts),
                          [.reply, .mention, .quote, .like, .repost,
                           .likeViaRepost, .repostViaRepost])
                    group(L(.notifyGroupAccount),
                          [.follow, .verified, .unverified, .starterpackJoined])

                    VStack(alignment: .leading, spacing: 12) {
                        group(L(.notifyGroupSubscriptions), [.subscribedPost])
                        Text(L(.notifySubscriptionsHint))
                            .font(Theme.Font.micro)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .task { await app.loadNotificationPreferences() }
    }

    // MARK: - One audience for the eight that have one

    @ViewBuilder
    private var audience: some View {
        let shared = app.notificationPreferences.sharedAudience
        let choice: AudienceChoice = shared.map {
            $0 == .all ? .all : .follows
        } ?? .mixed
        let options: [AudienceChoice] = shared == nil ? [.all, .follows, .mixed] : [.all, .follows]

        VStack(alignment: .leading, spacing: 10) {
            RelaySectionTitle(text: L(.notifyAudience))
            MonoSegment(selection: Binding(
                get: { choice },
                set: { picked in
                    guard picked != .mixed else { return }
                    var updated = app.notificationPreferences
                    updated.setAudience(picked == .all ? .all : .follows)
                    Task { await app.setNotificationPreferences(updated) }
                }),
                options: options, label: \.label, fills: true)
        }
    }

    // MARK: - Twelve rows, three states each

    @ViewBuilder
    private func group(_ title: String, _ kinds: [NotificationPreferences.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: title)
            ForEach(kinds) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.label(for: kind))
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    MonoSegment(selection: Binding(
                        get: { Level.of(app.notificationPreferences[kind]) },
                        set: { level in
                            var updated = app.notificationPreferences
                            updated[kind].list = level.applied.list
                            updated[kind].push = level.applied.push
                            Task { await app.setNotificationPreferences(updated) }
                        }),
                        options: Level.allCases, label: \.label, fills: true)
                }
            }
        }
    }

    static func label(for kind: NotificationPreferences.Kind) -> String {
        switch kind {
        case .reply: return L(.notifyKindReply)
        case .mention: return L(.notifyKindMention)
        case .quote: return L(.notifyKindQuote)
        case .like: return L(.notifyKindLike)
        case .repost: return L(.notifyKindRepost)
        case .likeViaRepost: return L(.notifyKindLikeViaRepost)
        case .repostViaRepost: return L(.notifyKindRepostViaRepost)
        case .follow: return L(.notifyKindFollow)
        case .verified: return L(.notifyKindVerified)
        case .unverified: return L(.notifyKindUnverified)
        case .starterpackJoined: return L(.notifyKindStarterpack)
        case .subscribedPost: return L(.notifyKindSubscribed)
        }
    }
}
