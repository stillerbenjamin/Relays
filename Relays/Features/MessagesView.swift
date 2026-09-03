//
//  MessagesView.swift
//  Relays
//
//  Direct messages. Conversations live on the chat service rather than in the
//  repository, so nothing here appears in the firehose or in an export.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ConversationsModel {
    private(set) var convos: [Convo] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Fills the model without a network round trip, for rendering previews.
    static func preview(_ convos: [Convo]) -> ConversationsModel {
        let model = ConversationsModel()
        model.convos = convos
        model.isLoading = false
        return model
    }

    /// Quiet or gone, straight from the list. Both are answers to somebody one
    /// does not want to hear from, and both belong where the conversation is.
    func toggleMute(_ convo: Convo, app: AppModel) async {
        let wasMuted = convo.muted == true
        apply(to: convo.id) { $0.muted = !wasMuted }
        do {
            if wasMuted { try await app.client.unmuteConversation(convoId: convo.id) }
            else { try await app.client.muteConversation(convoId: convo.id) }
        } catch {
            apply(to: convo.id) { $0.muted = wasMuted }
        }
    }

    func leave(_ convo: Convo, app: AppModel) async {
        let previous = convos
        convos.removeAll { $0.id == convo.id }
        do { try await app.client.leaveConversation(convoId: convo.id) }
        catch { convos = previous }
    }

    private func apply(to id: String, _ change: (inout Convo) -> Void) {
        guard let index = convos.firstIndex(where: { $0.id == id }) else { return }
        change(&convos[index])
    }

    func load(app: AppModel) async {
        errorMessage = nil
        do {
            convos = try await app.client.conversations().convos
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.report) private var report

    @State private var model: ConversationsModel
    @State private var showsNew = false
    /// Held while the question is on screen, so leaving is never one stray tap.
    @State private var leaving: Convo?

    @MainActor
    init(model: ConversationsModel? = nil) {
        self._model = State(initialValue: model ?? ConversationsModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.tabMessages),
                         onRefresh: { await model.load(app: app) }) {
                Button { showsNew = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.newMessage))
                .accessibilityLabel(L(.newMessage))
            }

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, model.convos.isEmpty {
                StateMessage(text: error, systemImage: "bubble.left.and.bubble.right") {
                    Task { await model.load(app: app) }
                }
                Spacer()
            } else if model.convos.isEmpty {
                StateMessage(text: L(.messagesEmpty), systemImage: "bubble.left.and.bubble.right")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.convos) { convo in
                            ConversationRow(convo: convo, mine: app.session?.did)
                                .onTapGesture { navigate(.conversation(id: convo.id)) }
                                .contextMenu {
                                    Button {
                                        Task { await model.toggleMute(convo, app: app) }
                                    } label: {
                                        Label(convo.muted == true ? L(.convoUnmute) : L(.convoMute),
                                              systemImage: convo.muted == true
                                                ? "speaker.wave.2" : "speaker.slash")
                                    }
                                    if let partner = convo.partner(excluding: app.session?.did) {
                                        Button {
                                            report(ReportTarget(kind: .account(partner)))
                                        } label: {
                                            Label(L(.moderationReport), systemImage: "flag")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        leaving = convo
                                    } label: {
                                        Label(L(.convoLeave), systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                            Hairline(inset: Theme.Metric.hPadding)
                        }
                    }
                }
                .scrollIndicators(.never)
                .refreshable { await model.load(app: app) }
            }
        }
        .relaysBackground()
        .confirmationDialog(L(.convoLeaveQuestion), isPresented: Binding(
            get: { leaving != nil },
            set: { if !$0 { leaving = nil } }), titleVisibility: .visible) {
            Button(L(.convoLeave), role: .destructive) {
                if let convo = leaving {
                    Task { await model.leave(convo, app: app) }
                }
                leaving = nil
            }
            Button(L(.cancel), role: .cancel) { leaving = nil }
        }
        .task { await model.load(app: app) }
        .sheet(isPresented: $showsNew) {
            NewConversationView { id in
                // The sheet is gone by the time this runs; a beat lets the
                // navigation animation start cleanly.
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    navigate(.conversation(id: id))
                }
            }
            .presentationBackground(Theme.Palette.background)
        }
    }
}

struct ConversationRow: View {
    let convo: Convo
    let mine: String?

    var body: some View {
        let partner = convo.partner(excluding: mine)
        let unread = convo.unreadCount ?? 0

        HStack(spacing: 12) {
            AvatarView(url: partner?.avatarURL, seed: partner?.handle ?? "?", size: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(partner?.name ?? "…")
                        .font(Theme.Font.ui(15, .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(RelativeTime.short(convo.lastMessage?.sentAt))
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Text(convo.lastMessage?.text ?? "")
                    .font(Theme.Font.ui(14))
                    .foregroundStyle(unread > 0 ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if convo.muted == true {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityLabel(L(.convoMuted))
            } else if unread > 0 {
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - One conversation

@MainActor
@Observable
final class ConversationModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var draft = ""
    private(set) var isSending = false

    static func preview(_ messages: [ChatMessage]) -> ConversationModel {
        let model = ConversationModel()
        model.messages = messages
        model.isLoading = false
        return model
    }

    func load(id: String, app: AppModel) async {
        do {
            // The service returns newest first; reading order is the other way.
            messages = try await app.client.messages(convoId: id).messages.reversed()
            try? await app.client.markConversationRead(convoId: id)
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func send(id: String, app: AppModel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            let sent = try await app.client.sendMessage(convoId: id, text: text)
            messages.append(sent)
            draft = ""
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ConversationView: View {
    let id: String

    @Environment(AppModel.self) private var app
    @Environment(\.report) private var report
    @State private var model: ConversationModel

    @MainActor
    init(id: String, model: ConversationModel? = nil) {
        self.id = id
        self._model = State(initialValue: model ?? ConversationModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.tabMessages), showsBack: true)

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, model.messages.isEmpty {
                StateMessage(text: error, systemImage: "bubble.left") {
                    Task { await model.load(id: id, app: app) }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.messages) { message in
                                MessageBubble(message: message, mine: message.isMine(app.session?.did))
                                    .id(message.id)
                                    .contextMenu {
                                        // Only somebody else's message can be
                                        // reported, and only the one message.
                                        if !message.isMine(app.session?.did),
                                           let did = message.sender?.did {
                                            Button {
                                                report(ReportTarget(kind: .message(
                                                    convoId: id, messageId: message.id, did: did,
                                                    handle: app.profileCache.profile(for: did)?.handle ?? did)))
                                            } label: {
                                                Label(L(.reportMessage), systemImage: "flag")
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: model.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                    }
                }
            }

            MessageComposer(draft: Binding(get: { model.draft }, set: { model.draft = $0 }),
                            isSending: model.isSending) {
                Task { await model.send(id: id, app: app) }
            }
        }
        .relaysBackground()
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task { await model.load(id: id, app: app) }
    }

}

/// One message. Mine sit right in the accent colour, theirs left on a surface.
struct MessageBubble: View {
    let message: ChatMessage
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 48) }

            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(mine ? Theme.Palette.onAccent : Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mine ? Theme.Palette.accent : Theme.Palette.surface)
                    )

                Text(RelativeTime.short(message.sentAt))
                    .font(Theme.Font.ui(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            if !mine { Spacer(minLength: 48) }
        }
    }
}


/// The field a message is written in, kept apart from the conversation so both
/// can be looked at on their own.
struct MessageComposer: View {
    @Binding var draft: String
    var isSending: Bool
    var onSend: () -> Void

    private var isEmpty: Bool { draft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                TextField(L(.messagePlaceholder), text: $draft, axis: .vertical)
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.Palette.surface))

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(isEmpty ? Theme.Palette.surface : Theme.Palette.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.send))
                .disabled(isEmpty || isSending)
                .accessibilityLabel(L(.send))
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 10)
        }
    }
}
