//
//  ComposeView.swift
//  Relays
//

import SwiftUI
import PhotosUI

struct ComposeView: View {
    let target: ComposeTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSending = false
    /// The rules the post will carry, chosen before it exists.
    @State private var replyRule: ReplyRule = .everybody
    @State private var allowsQuotes = true
    @State private var errorMessage: String?
    @State private var attachments: [ImageAttachment] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickedVideo: PhotosPickerItem?
    @State private var video: (data: Data, name: String)?
    @State private var videoProgress: Int?
    @State private var isPreparing = false
    @State private var altTarget: ImageAttachment?
    @State private var suggestions: [ActorProfile] = []
    @State private var suggestionTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private let limit = 300
    /// What the network accepts on one post.
    private let imageLimit = 4

    private var remaining: Int { limit - RichText.graphemeCount(text) }
    private var canSend: Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty || video != nil
        return hasContent && remaining >= 0 && !isSending && !isPreparing
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let quoted = target.quoting {
                QuotePreview(post: quoted)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.vertical, 12)
                Hairline()
            }

            if let parent = target.replyTo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(.composeReplyTo, parent.author.handle))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text(parent.record.text)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 12)
                Hairline()
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(target.replyTo == nil ? L(.composePlaceholder) : L(.composeReplyPlaceholder))
                        .font(Theme.Font.ui(15))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Metric.hPadding + 5)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(Theme.Font.ui(15))
                    .scrollIndicators(.never)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .tint(Theme.Palette.accent)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.top, 12)
                    .focused($focused)
            }

            if !suggestions.isEmpty {
                mentionSuggestions
            }

            if let video {
                videoRow(name: video.name)
            }

            if !attachments.isEmpty {
                attachmentStrip
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.bottom, 8)
            }

            footer
        }
        .relaysBackground()
        .relaysColorScheme()
        .sheetSize(.medium)
        .presentationBackground(Theme.Palette.background)
        .onAppear { focused = true }
        .onChange(of: picked) { _, items in
            Task { await adopt(items) }
        }
        .onChange(of: pickedVideo) { _, item in
            Task { await adoptVideo(item) }
        }
        .onChange(of: text) { _, value in
            updateSuggestions(for: value)
        }
        .sheet(item: $altTarget) { attachment in
            AltTextSheet(attachment: attachment)
                .presentationBackground(Theme.Palette.background)
                .sheetSize(.fixed(280))
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                Button(action: send) {
                    if isSending {
                        ProgressView().controlSize(.small).tint(Theme.Palette.background)
                    } else {
                        Text(L(.send))
                            .font(Theme.Font.micro)
                    }
                }
                .foregroundStyle(canSend ? Theme.Palette.background : Theme.Palette.textTertiary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Capsule().fill(canSend ? Theme.Palette.accent : Theme.Palette.surface)
                )
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 52)

            Hairline()
        }
    }

    @MainActor
    private var footer: some View {
        // Read on the main actor, used inside the pickers' labels, which are not.
        let accent = Theme.Palette.accent
        let dim = Theme.Palette.textTertiary
        let canAddImages = canAttachImages
        let canAddVideo = canAttachVideo

        return VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 14) {
                PhotosPicker(selection: $picked,
                             maxSelectionCount: imageLimit,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19))
                        .foregroundStyle(canAddImages ? accent : dim)
                }
                // Without this a PhotosPicker draws as a system bordered button
                // on macOS — grey chrome in the middle of the app's own design.
                .buttonStyle(.plain)
                .disabled(!canAttachImages)
                .accessibilityLabel(L(.composeAddImages))

                PhotosPicker(selection: $pickedVideo, matching: .videos, photoLibrary: .shared()) {
                    Image(systemName: "video")
                        .font(.system(size: 19))
                        .foregroundStyle(canAddVideo ? accent : dim)
                }
                .buttonStyle(.plain)
                .disabled(!canAttachVideo)
                .accessibilityLabel(L(.composeAddVideo))

                // Who may answer, and whether this may be quoted — decided with
                // the post, not after somebody has already replied.
                Menu {
                    ForEach(ReplyRule.offered) { rule in
                        Button {
                            replyRule = rule
                        } label: {
                            if replyRule == rule {
                                Label(rule.label, systemImage: "checkmark")
                            } else {
                                Text(rule.label)
                            }
                        }
                    }
                    Divider()
                    Button {
                        allowsQuotes.toggle()
                    } label: {
                        if allowsQuotes {
                            Label(L(.quotesAllowed), systemImage: "checkmark")
                        } else {
                            Text(L(.quotesAllowed))
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 15))
                        if replyRule != .everybody || !allowsQuotes {
                            Text(replyRule == .everybody ? L(.quotesDisabled) : replyRule.label)
                                .font(Theme.Font.mono(10))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(replyRule == .everybody && allowsQuotes
                                     ? Theme.Palette.textTertiary : Theme.Palette.accent)
                }
                .plainMenu()
                .accessibilityLabel(L(.replyWho))

                if isPreparing {
                    ProgressView().controlSize(.small).tint(Theme.Palette.textTertiary)
                }

                Spacer()

                Text("\(remaining)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(remaining < 0 ? Theme.Palette.danger : Theme.Palette.textTertiary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 52)
        }
    }

    /// One video at a time, and never alongside pictures — the record cannot hold both.
    private var canAttachImages: Bool { video == nil && attachments.count < imageLimit && !isPreparing }
    private var canAttachVideo: Bool { video == nil && attachments.isEmpty && !isPreparing }

    private func videoRow(name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Palette.surface))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Font.ui(14))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let videoProgress {
                    Text(L(.composeVideoProgress, videoProgress))
                        .font(Theme.Font.ui(12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            Spacer()

            Button {
                self.video = nil
                pickedVideo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(.composeRemoveImage))
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 10)
    }

    /// Videos are handed over as they are: the service transcodes them.
    private func adoptVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isPreparing = true
        defer { isPreparing = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = L(.composeVideoFailed)
            return
        }
        // The service caps uploads; refusing here beats failing after the wait.
        guard data.count <= 100_000_000 else {
            errorMessage = L(.composeVideoTooLarge)
            return
        }
        video = (data, "video.mp4")
    }

    /// Accounts matching the mention being typed. Tapping one completes it.
    private var mentionSuggestions: some View {
        VStack(spacing: 0) {
            Hairline()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { profile in
                        Button {
                            complete(with: profile)
                        } label: {
                            HStack(spacing: 7) {
                                AvatarView(url: profile.avatarURL, seed: profile.handle, size: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(profile.name)
                                        .font(Theme.Font.ui(13, .medium))
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                        .lineLimit(1)
                                    Text("@\(profile.handle)")
                                        .font(Theme.Font.ui(11))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Theme.Palette.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
        }
    }

    /// The mention being typed is the last word of the draft — which is where the
    /// cursor sits while writing. Editing further back is left alone rather than
    /// guessing at a cursor position SwiftUI does not expose.
    private var activeMention: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@"), last.count > 1,
              !last.contains("\n") else { return nil }
        return String(last.dropFirst())
    }

    private func updateSuggestions(for value: String) {
        suggestionTask?.cancel()
        guard let term = activeMention, term.count >= 2 else {
            suggestions = []
            return
        }

        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = (try? await app.client.typeahead(term: term)) ?? []
            guard !Task.isCancelled else { return }
            suggestions = found
        }
    }

    private func complete(with profile: ActorProfile) {
        guard let term = activeMention else { return }
        // Replace only the fragment being typed, keeping everything before it.
        if let range = text.range(of: "@\(term)", options: .backwards) {
            text.replaceSubrange(range, with: "@\(profile.handle) ")
        }
        suggestions = []
    }

    /// Chosen pictures, each removable and each able to carry a description.
    private var attachmentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = attachment.preview {
                                preview
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Theme.Palette.surface
                            }
                        }
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                attachments.removeAll { $0.id == attachment.id }
                                picked.removeAll()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.Palette.onMedia)
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .accessibilityLabel(L(.composeRemoveImage))
                    }
                    .overlay(alignment: .bottomLeading) {
                        Button { altTarget = attachment } label: {
                            Text(attachment.alt.isEmpty ? L(.composeAddAlt) : "ALT")
                                .font(Theme.Font.ui(10, .semibold))
                                .foregroundStyle(Theme.Palette.onMedia)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }

    /// Preparing happens off the main actor: scaling a photo is not instant.
    private func adopt(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isPreparing = true
        defer { isPreparing = false }

        var loaded: [ImageAttachment] = []
        for item in items.prefix(imageLimit) {
            if let attachment = await ImageAttachment.load(from: item) {
                loaded.append(attachment)
            }
        }
        guard !loaded.isEmpty else {
            errorMessage = L(.composeImageFailed)
            return
        }
        attachments = Array(loaded.prefix(imageLimit))
    }

    private func send() {
        guard canSend else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                let reply = target.replyTo.map { parent -> PostRecord.ReplyRefStrong in
                    let parentRef = StrongRef(uri: parent.uri, cid: parent.cid)
                    let rootRef = parent.record.reply?.root ?? parentRef
                    return PostRecord.ReplyRefStrong(root: rootRef, parent: parentRef)
                }

                // Every picture has to exist as a blob before the record can point at it.
                var images: ATProtoClient.ImagesEmbed?
                if !attachments.isEmpty {
                    var items: [ATProtoClient.ImagesEmbed.Item] = []
                    for attachment in attachments {
                        let blob = try await app.client.uploadBlob(data: attachment.data,
                                                                   mimeType: "image/jpeg")
                        items.append(.init(image: blob, alt: attachment.alt,
                                           aspectRatio: attachment.aspectRatio))
                    }
                    images = ATProtoClient.ImagesEmbed(images: items)
                }

                // A video goes through its own service and has to finish processing
                // before the record can reference it.
                var videoEmbed: ATProtoClient.VideoEmbed?
                if let video {
                    // Ask before sending. A refusal after a long upload on a slow
                    // connection is the worst way to learn about a daily limit.
                    if let limits = try? await app.client.videoUploadLimits(),
                       !limits.canUpload {
                        throw ATProtoError.videoFailed(limits.message ?? limits.error)
                    }
                    let job = try await app.client.uploadVideo(data: video.data, filename: video.name)
                    let blob = try await app.client.awaitVideo(job: job) { percent in
                        Task { @MainActor in videoProgress = percent }
                    }
                    videoEmbed = ATProtoClient.VideoEmbed(video: blob, alt: nil, aspectRatio: nil)
                    videoProgress = nil
                }

                let quote = target.quoting.map { StrongRef(uri: $0.uri, cid: $0.cid) }
                let embed = ATProtoClient.PostEmbedPayload.make(images: images, video: videoEmbed,
                                                                quoting: quote)

                let created = try await app.client.createPost(text: text, reply: reply,
                                                              embed: embed)

                // The rules for the new post are their own records, written once
                // the post exists and keyed to it. A failure here must not read
                // as a failure to post.
                if replyRule != .everybody {
                    try? await app.client.setReplyRules(ThreadGate(rules: [replyRule]),
                                                        forPost: created.uri)
                }
                if !allowsQuotes {
                    try? await app.client.setQuoteRules(allowed: false, forPost: created.uri)
                }

                if let parentUri = target.replyTo?.uri {
                    app.noteReplyAdded(to: parentUri)
                }
                if let quotedUri = target.quoting?.uri {
                    app.noteQuoteAdded(to: quotedUri)
                }
                dismiss()
            } catch {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }
}


/// A description for one picture. Bluesky treats alt text as part of posting,
/// not an afterthought, and so does this.
struct AltTextSheet: View {
    let attachment: ImageAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.composeAltTitle))
                    .font(Theme.Font.ui(17, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.close)) {
                    attachment.alt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .font(Theme.Font.ui(15, .medium))
                .foregroundStyle(Theme.Palette.link)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 56)
            Hairline()

            HStack(alignment: .top, spacing: 12) {
                if let preview = attachment.preview {
                    preview
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                TextField(L(.composeAltPlaceholder), text: $draft, axis: .vertical)
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(4, reservesSpace: true)
                    .textFieldStyle(.plain)
            }
            .padding(Theme.Metric.hPadding)

            Text(L(.composeAltHint))
                .font(Theme.Font.ui(13))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.hPadding)

            Spacer()
        }
        .relaysBackground()
        .relaysColorScheme()
        .onAppear { draft = attachment.alt }
    }
}


/// The post being quoted, shown while writing so it is clear what is attached.
struct QuotePreview: View {
    let post: PostView

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AvatarView(url: post.author.avatarURL, seed: post.author.handle, size: 20)
                Text(post.author.name)
                    .font(Theme.Font.ui(13, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("@\(post.author.handle)")
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Text(post.record.text)
                .font(Theme.Font.ui(14))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }
}
