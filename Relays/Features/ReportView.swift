//
//  ReportView.swift
//  Relays
//
//  Reporting a post or an account. Every app carrying other people's writing needs
//  this, and the App Store requires it.
//

import SwiftUI

struct ReportTarget: Identifiable {
    enum Kind {
        case post(PostView)
        case account(ActorProfile)
        /// A message has no URI. It is named by its conversation, itself and its
        /// sender — and since no profile comes with it, the handle travels along
        /// for the one line that shows it.
        case message(convoId: String, messageId: String, did: String, handle: String)
    }
    let kind: Kind

    var id: String {
        switch kind {
        case .post(let post): return post.uri
        case .account(let profile): return profile.did
        case .message(_, let messageId, _, _): return messageId
        }
    }

    var subject: ReportSubject {
        switch kind {
        case .post(let post): return .record(uri: post.uri, cid: post.cid)
        case .account(let profile): return .account(did: profile.did)
        case .message(let convoId, let messageId, let did, _):
            return .message(convoId: convoId, messageId: messageId, did: did)
        }
    }

    var title: String {
        switch kind {
        case .post: return L(.reportPost)
        case .account: return L(.reportAccount)
        case .message: return L(.reportMessage)
        }
    }

    var handle: String {
        switch kind {
        case .post(let post): return post.author.handle
        case .account(let profile): return profile.handle
        case .message(_, _, _, let handle): return handle
        }
    }
}

struct ReportView: View {
    let target: ReportTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ModerationReason = .spam
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false
    /// nil sends the report wherever the server sends it.
    @State private var destination: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if didSend {
                StateMessage(text: L(.reportSent), systemImage: "checkmark.circle")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("@\(target.handle)")
                            .font(Theme.Font.ui(15))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.horizontal, Theme.Metric.hPadding)
                            .padding(.top, 16)
                            .padding(.bottom, 14)

                        ForEach(ModerationReason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 17))
                                        .foregroundStyle(reason == option ? Theme.Palette.accent : Theme.Palette.textTertiary)
                                    Text(option.label)
                                        .font(Theme.Font.ui(15))
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Metric.hPadding)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hairline(inset: Theme.Metric.hPadding)
                        }

                        // Where the report goes. A subscribed service can be
                        // addressed instead of whichever one the server picks.
                        if !app.labelers.subscribed.isEmpty {
                            Hairline(inset: Theme.Metric.hPadding)
                            HStack {
                                Text(L(.reportTo))
                                    .font(Theme.Font.ui(15))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Spacer(minLength: 8)
                                Menu {
                                    Button(L(.reportToDefault)) { destination = nil }
                                    ForEach(app.labelers.subscribed, id: \.self) { did in
                                        Button(app.labelers.service(did)?.name ?? did) {
                                            destination = did
                                        }
                                    }
                                } label: {
                                    Text(destinationName)
                                        .font(Theme.Font.mono(12))
                                        .foregroundStyle(Theme.Palette.accent)
                                        .lineLimit(1)
                                }
                                .plainMenu()
                            }
                            .padding(.horizontal, Theme.Metric.hPadding)
                            .frame(height: 48)
                            Hairline(inset: Theme.Metric.hPadding)
                        }

                        TextField(L(.reportNote), text: $note, axis: .vertical)
                            .font(Theme.Font.ui(15))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.plain)
                            .padding(Theme.Metric.hPadding)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.danger)
                                .padding(.horizontal, Theme.Metric.hPadding)
                        }

                        MonoButton(title: L(.reportSend), isLoading: isSending, action: send)
                            .padding(.horizontal, Theme.Metric.hPadding)
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.never)
            }
        }
        .relaysBackground()
        .relaysColorScheme()
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(target.title)
                    .font(Theme.Font.ui(17, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.close)) { dismiss() }
                    .font(Theme.Font.ui(15, .medium))
                    .foregroundStyle(Theme.Palette.link)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 56)
            Hairline()
        }
    }

    /// The service the report is addressed to, or the server's own when nil.
    private var destinationName: String {
        guard let destination else { return L(.reportToDefault) }
        return app.labelers.service(destination)?.name ?? destination
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                try await app.report(target.subject, reason: reason, note: note,
                                     labeler: destination)
                didSend = true
                try? await Task.sleep(for: .seconds(1.4))
                dismiss()
            } catch {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }
}
