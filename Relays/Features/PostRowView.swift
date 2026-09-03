//
//  PostRowView.swift
//  Relays
//

import SwiftUI

/// A single post, in list or detail presentation.
struct PostRowView: View {
    let post: PostView
    var repostedBy: ActorProfile?
    /// The account this post answers, when it appears outside its thread.
    var replyingTo: ActorProfile?
    var isDetail: Bool = false
    var onOpenThread: (PostView) -> Void = { _ in }
    var onOpenProfile: (ActorProfile) -> Void = { _ in }
    var onReply: (PostView) -> Void = { _ in }
    /// Opening the post this one answers needs only its URI.
    var onOpenURI: (String) -> Void = { _ in }
    /// Who quoted this post — offered only where there is somebody.
    var onOpenQuotes: (PostView) -> Void = { _ in }
    /// The accounts behind the two other counters. The heart has to stay a
    /// one-tap toggle, so neither number is tappable itself — both lists hang
    /// in menus.
    var onOpenActors: (PostView, ActorListKind) -> Void = { _, _ in }
    /// The post this thread hangs from. Set on replies, so their author's author
    /// can fold them away.
    var threadRoot: PostView?

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.inspectRecord) private var inspectRecord
    @Environment(\.report) private var report
    @Environment(\.composeAction) private var compose

    @State private var showsDeleteConfirm = false

    private var state: PostState { app.state(for: post) }
    private var origin: AccountOrigin? {
        settings.showPDSOrigin ? app.directory.origin(for: post.author.did) : nil
    }
    private var avatarSize: CGFloat { settings.compactMode ? 38 : Theme.Metric.avatar }
    private var rowPadding: CGFloat { settings.compactMode ? 10 : 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let repostedBy {
                Label {
                    Text(L(.feedRepostedBy, repostedBy.name))
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.leading, avatarSize + Theme.Metric.avatarGap)
                .padding(.bottom, 2)
            }

            if let replyingTo, repostedBy == nil {
                Button {
                    if let parent = post.record.reply?.parent.uri {
                        onOpenURI(parent)
                    } else {
                        onOpenProfile(replyingTo)
                    }
                } label: {
                    Label {
                        Text(L(.replyingTo, replyingTo.handle))
                            .font(Theme.Font.ui(13))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, avatarSize + Theme.Metric.avatarGap)
                .padding(.bottom, 2)
            }

            HStack(alignment: .top, spacing: Theme.Metric.avatarGap) {
                Button { onOpenProfile(post.author) } label: {
                    AvatarView(url: post.author.avatarURL, seed: post.author.handle, size: avatarSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(post.author.name)
                .accessibilityHint(L(.tabProfile))

                VStack(alignment: .leading, spacing: 3) {
                    header

                    let decision = app.effectiveDecision(for: post)

                    if decision.warns || decision.blursContent {
                        ModerationNotice(decision: decision, uri: post.uri)
                            .padding(.top, 3)
                    }

                    if let notice = replyNotice {
                        Label(notice, systemImage: "bubble.left.and.bubble.right")
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.top, 2)
                    }

                    // A covered post keeps its header and its actions: the reader
                    // can still see who wrote it and step past the cover.
                    if !decision.blursContent {
                        if !post.record.text.isEmpty {
                            RichTextView(text: post.record.text,
                                         facets: post.record.facets,
                                         font: isDetail ? Theme.Font.ui(17) : Theme.Font.body)
                                .padding(.top, 1)
                        }
                        if let labels = post.labels, !labels.isEmpty {
                            labelChips(labels)
                        }
                        if let embed = post.embed, embed.isRenderable {
                            EmbedView(embed: embed)
                                .padding(.top, 6)
                                .fixedSize(horizontal: false, vertical: true)
                                .modifier(MediaCover(decision: decision, uri: post.uri))
                        }
                    }

                    actions
                        .padding(.top, 8)
                        // The actions stay their own elements. Everything above
                        // them is one: read out as a post, not as an avatar, a
                        // name, a handle, an age and a paragraph.
                        .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spokenSummary)
        .task(id: post.author.did) {
            if settings.showPDSOrigin { app.directory.resolve(post.author.did) }
            // Only the author's own rules can be read, and only they need them.
            if isOwnPost { await app.loadGate(for: post) }
        }
        .onTapGesture { if !isDetail { onOpenThread(post) } }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.tap(enabled: settings.haptics)
            inspectRecord(post)
        }
        .contextMenu { menu }
        .confirmationDialog(L(.moderationDeleteQuestion),
                            isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button(L(.moderationDelete), role: .destructive) {
                Task { await app.deletePost(post) }
            }
            Button(L(.cancel), role: .cancel) {}
        }
    }

    /// Everything one can do with someone else's writing — and with one's own.
    @ViewBuilder
    private var menu: some View {
        Button {
            inspectRecord(post)
        } label: {
            Label(L(.inspect), systemImage: "curlybraces")
        }

        // The heart is a toggle and must stay one, so the accounts behind its
        // number are reached from here instead. Offered only where there are any.
        if state.likeCount > 0 {
            Button {
                onOpenActors(post, .likes)
            } label: {
                Label(L(.seeLikes), systemImage: "heart")
            }
        }

        if isOwnPost {
            Divider()

            // The author's own rules for this post: who may answer it, and
            // whether it may be quoted.
            Menu {
                ForEach(ReplyRule.offered) { rule in
                    Button {
                        Task { await app.setReplyRule(rule, for: post) }
                    } label: {
                        if app.gate(for: post).rules.first == rule {
                            Label(rule.label, systemImage: "checkmark")
                        } else {
                            Text(rule.label)
                        }
                    }
                }
            } label: {
                Label(L(.replyWho), systemImage: "bubble.left.and.bubble.right")
            }

            Button {
                Task { await app.toggleQuotes(for: post) }
            } label: {
                Label(quotesOn ? L(.quotesDisabled) : L(.quotesAllowed),
                      systemImage: quotesOn ? "quote.closing" : "quote.opening")
            }

            Button(role: .destructive) {
                showsDeleteConfirm = true
            } label: {
                Label(L(.moderationDelete), systemImage: "trash")
            }
        } else {
            Divider()

            Button {
                Task { await app.toggleHidden(post) }
            } label: {
                Label(app.hiddenPosts.contains(post.uri) ? L(.unhidePost) : L(.hidePost),
                      systemImage: "eye.slash")
            }

            // Only in a thread one started: folding a reply away is the author's
            // own moderation, and it applies to everyone reading the thread.
            if let root = threadRoot, root.author.did == app.session?.did {
                Button {
                    Task { await app.toggleHiddenReply(post, inThreadOf: root) }
                } label: {
                    Label(app.gate(for: root).hiddenReplies.contains(post.uri)
                          ? L(.unhideReply) : L(.hideReply),
                          systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }

            Button {
                report(ReportTarget(kind: .post(post)))
            } label: {
                Label(L(.moderationReport), systemImage: "flag")
            }

            Button {
                Task { await app.toggleMute(post.author) }
            } label: {
                Label(app.isMuted(post.author.did) ? L(.moderationUnmute) : L(.moderationMute),
                      systemImage: app.isMuted(post.author.did) ? "speaker.wave.2" : "speaker.slash")
            }

            Button(role: .destructive) {
                Task { await app.toggleBlock(post.author) }
            } label: {
                Label(app.isBlocked(post.author.did) ? L(.moderationUnblock) : L(.moderationBlock),
                      systemImage: "hand.raised")
            }
        }
    }

    private var isOwnPost: Bool { post.author.did == app.session?.did }

    /// The post as one sentence: who wrote it, when, and what it says. The
    /// counts are left to the action buttons, which say them anyway.
    private var spokenSummary: String {
        var parts: [String] = [post.author.name]
        if let repostedBy { parts.insert(L(.feedRepostedBy, repostedBy.name), at: 0) }
        if let replyingTo { parts.append(L(.replyingTo, replyingTo.handle)) }
        parts.append(RelativeTime.short(post.record.createdAt ?? post.indexedAt))

        let decision = app.effectiveDecision(for: post)
        if decision.blursContent || decision.warns, let reason = decision.reason {
            parts.append(reason)
        }
        if !decision.blursContent, !post.record.text.isEmpty {
            parts.append(post.record.text)
        }
        if let quoted = post.embed?.quoted, let author = quoted.author {
            parts.append(L(.a11yQuoteOf, author.name))
            if let text = quoted.value?.text, !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: ", ")
    }

    /// Why a reader cannot answer here. For one's own posts this comes from the
    /// record, for everyone else's from what the server allows this reader.
    private var replyNotice: String? {
        if isOwnPost { return app.gate(for: post).summary }
        return post.viewer?.replyDisabled == true ? L(.replyDisabled) : nil
    }

    /// What the app currently believes about quoting this post.
    private var quotesOn: Bool {
        app.quotesAllowed[post.uri] ?? (post.viewer?.embeddingDisabled != true)
    }

    /// Name, handle and age on one line, separated by a middot — the shape readers
    /// of this layout already parse without thinking.
    private var header: some View {
        HStack(spacing: 4) {
            Text(post.author.name)
                .font(Theme.Font.ui(15, .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            VerificationBadge(verification: post.author.verification, size: 14)

            Text("@\(post.author.handle)")
                .font(Theme.Font.ui(15))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .layoutPriority(-1)

            Text("·")
                .font(Theme.Font.ui(15))
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(RelativeTime.short(post.record.createdAt ?? post.indexedAt))
                .font(Theme.Font.ui(15))
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize()

            if let origin, !origin.isBlueskyHosted {
                Text(origin.short)
                    .font(Theme.Font.ui(11, .medium))
                    .foregroundStyle(Theme.Palette.link)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Palette.link.opacity(0.12)))
                    .lineLimit(1)
                    .accessibilityLabel(L(.hostedOn, origin.host))
            }

            Spacer(minLength: 0)
        }
    }

    /// Moderation labels a labeler attached to this post.
    private func labelChips(_ labels: [ContentLabel]) -> some View {
        HStack(spacing: 5) {
            ForEach(labels.prefix(3)) { label in
                Text(label.val.replacingOccurrences(of: "-", with: " "))
                    .font(Theme.Font.ui(11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.Palette.surface))
            }
        }
        .padding(.top, 4)
    }

    /// Reply, repost, like — spread across the text column, each colouring only
    /// when it is the reader\'s own.
    /// Each action sits in an equal share of the text column, so the icons line up
    /// at fixed intervals no matter how wide the counts beside them are.
    private var actions: some View {
        HStack(spacing: 0) {
            actionButton(icon: "bubble.left",
                         count: state.replyCount,
                         tint: Theme.Palette.link,
                         active: false,
                         label: L(.actionReply)) {
                onReply(post)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            repostControl
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(icon: state.isLiked ? "heart.fill" : "heart",
                         count: state.likeCount,
                         tint: Theme.Palette.like,
                         active: state.isLiked,
                         label: state.isLiked ? L(.actionUnlike) : L(.actionLike)) {
                Haptics.tap(enabled: settings.haptics)
                Task { await app.toggleLike(post) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 8)
    }

    /// Repost or quote. Two platforms, two idioms: a menu on iOS, where that is
    /// what a menu looks like, and the app's own panel on macOS, where a Menu
    /// draws itself as a bordered pop-up button.
    @ViewBuilder
    private var repostControl: some View {
        #if os(macOS)
        AppPopover {
            actionLabel(icon: "arrow.2.squarepath",
                        count: state.sharedCount,
                        tint: Theme.Palette.repost,
                        active: state.isReposted)
        } content: { close in
            AppPopoverRow(title: state.isReposted ? L(.actionUndoRepost) : L(.actionRepost),
                          systemImage: "arrow.2.squarepath",
                          isSelected: state.isReposted) {
                close()
                Task { await app.toggleRepost(post) }
            }
            AppPopoverRow(title: L(.actionQuote), systemImage: "quote.opening") {
                close()
                compose(ComposeTarget(replyTo: nil, quoting: post))
            }
            if state.quoteCount > 0 {
                AppPopoverRow(title: L(.quotesTitle), systemImage: "text.quote") {
                    close()
                    onOpenQuotes(post)
                }
            }
            if state.sharedCount > 0 {
                AppPopoverRow(title: L(.seeReposts), systemImage: "person.2") {
                    close()
                    onOpenActors(post, .reposts)
                }
            }
        }
        .accessibilityLabel(L(.actionRepost))
        .accessibilityValue(state.sharedCount > 0 ? "\(state.sharedCount)" : "")
        .accessibilityAddTraits(state.isReposted ? .isSelected : [])
        #else
        Menu {
            Button {
                Haptics.tap(enabled: settings.haptics)
                Task { await app.toggleRepost(post) }
            } label: {
                Label(state.isReposted ? L(.actionUndoRepost) : L(.actionRepost),
                      systemImage: "arrow.2.squarepath")
            }
            Button {
                compose(ComposeTarget(replyTo: nil, quoting: post))
            } label: {
                Label(L(.actionQuote), systemImage: "quote.opening")
            }
            if state.quoteCount > 0 {
                Button {
                    onOpenQuotes(post)
                } label: {
                    Label(L(.quotesTitle), systemImage: "text.quote")
                }
            }
            if state.sharedCount > 0 {
                Button {
                    onOpenActors(post, .reposts)
                } label: {
                    Label(L(.seeReposts), systemImage: "person.2")
                }
            }
        } label: {
            actionLabel(icon: "arrow.2.squarepath",
                        count: state.sharedCount,
                        tint: Theme.Palette.repost,
                        active: state.isReposted)
        }
        .accessibilityLabel(L(.actionRepost))
        .accessibilityValue(state.sharedCount > 0 ? "\(state.sharedCount)" : "")
        .accessibilityAddTraits(state.isReposted ? .isSelected : [])
        #endif
    }

    private func actionButton(icon: String, count: Int, tint: Color, active: Bool,
                              label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(icon: icon, count: count, tint: tint, active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        // Without this a liked and an unliked post sound identical.
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The visual half of an action, shared by the plain buttons and the repost menu.
    private func actionLabel(icon: String, count: Int, tint: Color, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            if count > 0 && settings.showCounts {
                Text(Format.compact(count))
                    .font(Theme.Font.ui(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(active ? tint : Theme.Palette.textSecondary)
        .animation(.easeOut(duration: 0.15), value: active)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

}

/// Renders post text with tappable links, mentions and tags.
/// `autoLink` detects links in plain strings that carry no facets, such as profile bios.
struct RichTextView: View {
    let text: String
    var facets: [Facet]? = nil
    var font: Font = Theme.Font.body
    var color: Color = Theme.Palette.textPrimary
    var autoLink: Bool = false

    @Environment(\.openLink) private var openLink
    @Environment(\.navigate) private var navigate

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(3)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if let actor = Self.actorReference(in: url) {
                    navigate(.profile(actor: actor))
                } else if let tag = Self.tagReference(in: url) {
                    navigate(.hashtag(tag))
                } else {
                    openLink(url)
                }
                return .handled
            })
    }

    private var segments: [RichText.Segment] {
        autoLink ? RichText.autoLinkedSegments(in: text)
                 : RichText.segments(text: text, facets: facets)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in segments {
            switch segment {
            case .text(let value):
                result.append(AttributedString(value))

            case .link(let value, let url):
                var part = AttributedString(value)
                part.link = url
                part.foregroundColor = Theme.Palette.link
                result.append(part)

            case .mention(let value, let actor):
                var part = AttributedString(value)
                part.link = Self.actorURL(actor)
                part.foregroundColor = Theme.Palette.link
                result.append(part)

            case .tag(let value, let tag):
                var part = AttributedString(value)
                part.link = Self.tagURL(tag)
                part.foregroundColor = Theme.Palette.link
                result.append(part)
            }
        }
        return result
    }

    /// Internal scheme so mentions travel through the same tap handling as links.
    private static func actorURL(_ actor: String) -> URL? {
        var components = URLComponents()
        components.scheme = "relays"
        components.host = "profile"
        components.queryItems = [URLQueryItem(name: "id", value: actor)]
        return components.url
    }

    private static func actorReference(in url: URL) -> String? {
        reference(in: url, host: "profile", key: "id")
    }

    private static func tagURL(_ tag: String) -> URL? {
        var components = URLComponents()
        components.scheme = "relays"
        components.host = "tag"
        components.queryItems = [URLQueryItem(name: "name", value: tag)]
        return components.url
    }

    private static func tagReference(in url: URL) -> String? {
        reference(in: url, host: "tag", key: "name")
    }

    private static func reference(in url: URL, host: String, key: String) -> String? {
        guard url.scheme == "relays", url.host == host else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == key })?.value
    }
}

/// Images, link previews and quotes.
struct EmbedView: View {
    let embed: PostEmbed
    /// Kept so a tapped tile can open the whole set at the right index.
    private var images: [EmbedImage] {
        if case .images(let items) = embed { return items }
        return []
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.openImages) private var openImages
    @Environment(\.navigate) private var navigate

    var body: some View {
        switch embed {
        case .images(let images):
            if settings.showImages {
                imageGrid(images)
            } else {
                altTextList(images)
            }
        case .video(let video):
            VideoCard(video: video)
        case .external(let external):
            LinkPreviewCard(external: external)
        case .record(let record):
            if let record { recordCard(record) }
        case .recordWithMedia(let media, let record):
            // Both halves, in the order they were written: the picture, then the
            // post it was said about.
            VStack(alignment: .leading, spacing: 8) {
                if media.isRenderable { EmbedView(embed: media) }
                if let record { recordCard(record) }
            }
        case .unsupported:
            EmptyView()
        }
    }

    /// Images are laid out at the aspect ratio the network reports, not squeezed
    /// into a fixed height — that mismatch is what left a gap under wide photos.
    @ViewBuilder
    private func imageGrid(_ images: [EmbedImage]) -> some View {
        let shown = Array(images.prefix(4))

        Group {
            switch shown.count {
            case 1:
                tile(shown[0], ratio: ratio(of: shown[0]))

            case 2:
                HStack(spacing: 3) {
                    tile(shown[0], ratio: 1)
                    tile(shown[1], ratio: 1)
                }

            case 3:
                VStack(spacing: 3) {
                    tile(shown[0], ratio: 16 / 9)
                    HStack(spacing: 3) {
                        tile(shown[1], ratio: 1)
                        tile(shown[2], ratio: 1)
                    }
                }

            default:
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        tile(shown[0], ratio: 1)
                        tile(shown[1], ratio: 1)
                    }
                    HStack(spacing: 3) {
                        tile(shown[2], ratio: 1)
                        tile(shown[3], ratio: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Media takes exactly the height its ratio calls for and no more.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Very tall or very wide images are reined in so one post cannot take over
    /// the whole screen.
    private func ratio(of image: EmbedImage) -> CGFloat {
        guard let aspect = image.aspectRatio, aspect.height > 0 else { return 16 / 9 }
        return min(max(CGFloat(aspect.width) / CGFloat(aspect.height), 0.75), 2.0)
    }

    private func tile(_ image: EmbedImage, ratio: CGFloat) -> some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                AsyncImage(url: image.thumbURL) { phase in
                    switch phase {
                    case .success(let rendered):
                        rendered.resizable().scaledToFill()
                    default:
                        Theme.Palette.surface
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if let index = images.firstIndex(of: image) {
                    openImages(images, at: index)
                }
            }
            // The alt text is the picture, to anybody who cannot see it. Where
            // the author wrote none, at least say that a picture is there.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(image.alt?.isEmpty == false ? image.alt! : L(.a11yPostImage))
            .overlay(alignment: .bottomLeading) {
                if settings.showAltBadge, let alt = image.alt, !alt.isEmpty {
                    Text("ALT")
                        .font(Theme.Font.ui(10, .semibold))
                        .foregroundStyle(Theme.Palette.onMedia)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .padding(8)
                }
            }
            .accessibilityLabel(image.alt ?? L(.loadingImages))
    }

    /// With images off the alt text carries the information.
    private func altTextList(_ images: [EmbedImage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(images) { image in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                    Text(image.alt?.isEmpty == false ? image.alt! : L(.loadingImages))
                        .font(Theme.Font.micro)
                        .lineLimit(2)
                }
                .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.top, 2)
    }

    /// Eight things can sit on the other end of an embedded record. Seven of
    /// them used to draw nothing at all — and a `viewNotFound` drew worse than
    /// nothing: an empty bordered box, because every field of a quoted post is
    /// optional and so decoding one always succeeded.
    @ViewBuilder
    private func recordCard(_ record: EmbeddedRecord) -> some View {
        switch record {
        case .post(let quoted):
            quoteCard(quoted)
        case .feed(let feed):
            objectCard(kind: L(.embedFeed), title: feed.displayName,
                       subtitle: feed.description, avatar: feed.avatarURL,
                       seed: feed.uri ?? "", by: feed.creator,
                       detail: feed.likeCount.map { L(.embedLikes, Format.compact($0)) },
                       uri: feed.uri)
        case .list(let list):
            objectCard(kind: L(.embedList), title: list.name,
                       subtitle: list.description, avatar: list.avatarURL,
                       seed: list.uri ?? "", by: list.creator,
                       detail: list.listItemCount.map { L(.listMembers, $0) },
                       uri: list.uri)
        case .starterPack(let pack):
            objectCard(kind: L(.embedStarterPack), title: pack.name,
                       subtitle: pack.record?.description, avatar: nil,
                       seed: pack.uri ?? "", by: pack.creator,
                       detail: pack.joinedAllTimeCount.map { L(.embedJoined, Format.compact($0)) },
                       uri: pack.uri)
        case .labeler(let labeler):
            objectCard(kind: L(.labelersIsLabeler), title: labeler.creator?.name,
                       subtitle: labeler.creator?.description, avatar: labeler.creator?.avatarURL,
                       seed: labeler.creator?.handle ?? "", by: nil,
                       detail: labeler.likeCount.map { L(.embedLikes, Format.compact($0)) },
                       uri: labeler.uri)
        case .notFound:
            missingCard(L(.embedNotFound), symbol: "trash")
        case .blocked:
            missingCard(L(.embedBlocked), symbol: "hand.raised")
        case .detached:
            missingCard(L(.embedDetached), symbol: "link.badge.plus")
        case .unknown:
            EmptyView()
        }
    }

    /// A feed, a list, a starter pack or a moderation service. All four read the
    /// same way: what it is, what it is called, who made it, how big it is.
    @ViewBuilder
    private func objectCard(kind: String, title: String?, subtitle: String?,
                            avatar: URL?, seed: String, by: ActorProfile?,
                            detail: String?, uri: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(url: avatar, seed: seed, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.uppercased())
                    .font(Theme.Font.mono(9))
                    .foregroundStyle(Theme.Palette.textTertiary)

                Text(title ?? kind)
                    .font(Theme.Font.ui(12, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 8) {
                    if let by {
                        Text("@\(by.handle)")
                            .font(Theme.Font.micro)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                    }
                    if let detail {
                        Text(detail)
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    /// Not content, but the reason there is none. Saying it is the whole point —
    /// an unexplained gap reads as a bug in the app.
    private func missingCard(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(text)
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func quoteCard(_ quoted: QuotedPost) -> some View {
        Button {
            if let uri = quoted.uri { navigate(.thread(uri: uri)) }
        } label: {
            quoteBody(quoted)
        }
        .buttonStyle(.plain)
        .disabled(quoted.uri == nil)
    }

    private func quoteBody(_ quoted: QuotedPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let author = quoted.author {
                HStack(spacing: 6) {
                    AvatarView(url: author.avatarURL, seed: author.handle, size: 18)
                    Text(author.name)
                        .font(Theme.Font.ui(11, .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("@\(author.handle)")
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            if let text = quoted.value?.text, !text.isEmpty {
                Text(text)
                    .font(Theme.Font.ui(12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 2)
    }
}

// MARK: - Moderation

/// The line above a post that a label warned about, and the cover over one that
/// a label hid. Both say which layer decided, because a moderation decision with
/// no author is indistinguishable from a bug.
struct ModerationNotice: View {
    let decision: ModerationDecision
    let uri: String

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: decision.blursContent ? "eye.slash" : "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(decision.reason ?? L(.moderationCovered))
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let origin {
                    Text(origin)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            Spacer(minLength: 8)

            if decision.verdict.isRevealable || app.revealed.contains(uri) {
                Button { app.toggleReveal(uri) } label: {
                    Text(app.revealed.contains(uri) ? L(.moderationHide) : L(.moderationShowAnyway))
                        .font(Theme.Font.ui(12))
                        .foregroundStyle(Theme.Palette.link)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Palette.surface)
        )
    }

    private var origin: String? {
        switch decision.source {
        case .selfLabel: return L(.moderationSelfLabel)
        case .labeler: return L(.moderationByLabeler)
        case .device: return L(.moderationByDevice)
        case .mutedWord: return L(.moderationByWord)
        case .hiddenPost: return nil
        case .account, .none: return nil
        }
    }
}

/// Covers the pictures without touching the layout underneath them, so a post
/// does not jump when the reader uncovers it.
struct MediaCover: ViewModifier {
    let decision: ModerationDecision
    let uri: String

    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        if decision.blursMedia {
            content
                .overlay {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Rectangle().fill(Theme.Palette.mediaScrim)
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 15))
                            Text(decision.reason ?? L(.moderationCovered))
                                .font(Theme.Font.ui(12, .medium))
                            Text(L(.moderationShowAnyway))
                                .font(Theme.Font.ui(12))
                                .opacity(0.85)
                        }
                        .foregroundStyle(Theme.Palette.onMedia)
                        .padding(10)
                        .multilineTextAlignment(.center)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius,
                                                style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { app.toggleReveal(uri) }
                }
        } else {
            content
        }
    }
}
