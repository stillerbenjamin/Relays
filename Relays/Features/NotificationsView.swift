//
//  NotificationsView.swift
//  Relays
//

import SwiftUI
import Observation

@MainActor
@Observable
final class NotificationsModel {
    private(set) var items: [ATNotification] = []
    private(set) var isLoading = true
    private(set) var isPaging = false
    private(set) var errorMessage: String?

    private var cursor: String?
    private var reachedEnd = false
    /// One load at a time. Pull-to-refresh, the header button and the first
    /// `.task` could all run at once, and the slowest writer won.
    private var loading = false

    func load(app: AppModel) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        errorMessage = nil
        do {
            let page = try await app.client.notifications()
            items = page.notifications
            cursor = page.cursor
            reachedEnd = page.cursor == nil
            page.notifications.forEach { app.register(moderationOf: $0.author) }
        } catch {
            // The list is left standing: an error over content that is already
            // there is a message, not a reason to blank the screen.
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Older ones. The screen used to stop at the first forty with nothing to
    /// say so — the cursor was decoded and thrown away.
    func loadMore(app: AppModel) async {
        guard !isPaging, !reachedEnd, !loading, let cursor else { return }
        isPaging = true
        defer { isPaging = false }

        do {
            let page = try await app.client.notifications(cursor: cursor)
            let known = Set(items.map(\.id))
            items += page.notifications.filter { !known.contains($0.id) }
            self.cursor = page.cursor
            // Keyed off the page the server sent, not off whether the visible
            // list grew — moderation can empty a page without it being the end.
            reachedEnd = page.cursor == nil || page.notifications.isEmpty
            page.notifications.forEach { app.register(moderationOf: $0.author) }
        } catch {
            reachedEnd = true
        }
    }

    /// A muted or blocked account's like still arrived here; every other list in
    /// the app filters and this one did not.
    func visible(app: AppModel) -> [ATNotification] {
        items.filter { !app.isHidden($0.author.did) }
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    @State private var model = NotificationsModel()

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.tabNotifications),
                         onRefresh: { await model.load(app: app) })

            let shown = model.visible(app: app)

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, shown.isEmpty {
                StateMessage(text: error, systemImage: "bell.slash") {
                    Task { await model.load(app: app) }
                }
                Spacer()
            } else if shown.isEmpty {
                StateMessage(text: L(.notificationsEmpty), systemImage: "bell") {
                    Task { await model.load(app: app) }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // A refresh that failed over a list that is already
                        // there says so, instead of redrawing in silence.
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.micro)
                                .foregroundStyle(Theme.Palette.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Metric.hPadding)
                                .padding(.vertical, 8)
                        }

                        ForEach(shown) { item in
                            row(item)
                            Hairline()
                                .onAppear {
                                    if item.id == shown.last?.id {
                                        Task { await model.loadMore(app: app) }
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
                .refreshable { await model.load(app: app) }
            }
        }
        .relaysBackground()
        .task { await model.load(app: app) }
    }

    private func row(_ item: ATNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    AvatarView(url: item.author.avatarURL, seed: item.author.handle, size: 20)
                    Text(item.author.name)
                        .font(Theme.Font.ui(12, .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(item.verb)
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 4)
                    Text(RelativeTime.short(item.indexedAt))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                if let text = item.record?.text, !text.isEmpty {
                    Text(text)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 12)
        .background(item.isRead ? Color.clear : Theme.Palette.surface.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {
            // `postToOpen` knows that a reply's subject is *your* post while the
            // reply itself is the notification's own uri. Tapping "replied" used
            // to open what was replied to rather than the reply.
            if let uri = item.postToOpen {
                navigate(.thread(uri: uri))
            } else {
                navigate(.profile(actor: item.author.did))
            }
        }
    }
}
