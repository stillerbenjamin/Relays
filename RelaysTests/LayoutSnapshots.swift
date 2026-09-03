//
//  LayoutSnapshots.swift
//  RelaysTests
//
//  Renders the real views with fixed sample data and writes PNGs into the host
//  app's documents directory. This is how the layout can be looked at without
//  signing in to a live account.
//
//  Remote images do not load inside a renderer, so avatars and banners fall back
//  to their placeholders — the arrangement is what these show.
//

import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import Relays

@MainActor
@Suite("Layout snapshots")
struct LayoutSnapshots {

    // MARK: - Sample data

    private func author(_ handle: String, _ name: String, followers: Int = 0) -> ActorProfile {
        ActorProfile(did: "did:plc:\(handle.prefix(6))", handle: handle, displayName: name,
                     avatar: nil, banner: nil,
                     description: nil, followersCount: followers, followsCount: nil,
                     postsCount: nil, viewer: nil)
    }

    private func post(_ author: ActorProfile, _ text: String, minutesAgo: Int,
                      replies: Int, reposts: Int, likes: Int,
                      liked: Bool = false, facets: [Facet]? = nil,
                      embed: PostEmbed? = nil) -> FeedViewPost {
        let created = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
        let view = PostView(
            uri: "at://\(author.did)/app.bsky.feed.post/\(UUID().uuidString.prefix(8))",
            cid: "bafy", author: author,
            record: PostRecord(text: text, createdAt: created, facets: facets),
            embed: embed, replyCount: replies, repostCount: reposts, likeCount: likes,
            indexedAt: created,
            viewer: liked ? PostViewerState(like: "at://like", repost: nil) : nil,
            labels: nil)
        return FeedViewPost(post: view, reply: nil, reason: nil)
    }

    private var samplePosts: [FeedViewPost] {
        let jay = author("jay.bsky.team", "Jay")
        let maria = author("maria.dev", "Maria Lindqvist")
        let hosted = author("anna.pds.example.com", "Anna Weiß")
        let alex = author("alex.bsky.social", "Alex")

        // A link facet, so the rich-text path is exercised too.
        let linkText = "Der Firehose-Endpunkt ist offen: https://jetstream2.us-east.bsky.network"
        let bytes = Array(linkText.utf8)
        let start = bytes.count - Array("https://jetstream2.us-east.bsky.network".utf8).count
        let facet = Facet(index: .init(byteStart: start, byteEnd: bytes.count),
                          features: [.link(uri: "https://jetstream2.us-east.bsky.network")])

        return [
            post(jay, "Ein offenes Protokoll heißt: Du kannst gehen und nimmst alles mit. Kein Anbieter dazwischen.",
                 minutesAgo: 4, replies: 18, reposts: 42, likes: 315),
            post(maria, linkText, minutesAgo: 26, replies: 3, reposts: 11, likes: 68,
                 liked: true, facets: [facet]),
            post(hosted, "Läuft seit gestern auf dem eigenen PDS. Migration hat elf Minuten gedauert.",
                 minutesAgo: 95, replies: 7, reposts: 4, likes: 51),
            post(alex, "Guten Morgen ☕️",
                 minutesAgo: 240, replies: 1, reposts: 0, likes: 9),
            {
                // Facets detected the same way the composer produces them.
                let text = "Neuer Beitrag über #atproto und #dezentral — Feedback willkommen"
                return post(author("nina.bsky.social", "Nina Roth"), text,
                            minutesAgo: 320, replies: 4, reposts: 8, likes: 47,
                            facets: RichText.detectFacets(in: text))
            }()
        ]
    }

    /// One image, with the aspect ratio the network reports — the case where a
    /// gap was showing up underneath the post.
    private var postWithImage: FeedViewPost {
        let image = EmbedImage(thumb: nil, fullsize: nil, alt: "Ein Diagramm",
                               aspectRatio: .init(width: 1600, height: 900))
        return post(author("tom.bsky.social", "Tom Berger"),
                    "Durchsatz der letzten Woche:",
                    minutesAgo: 12, replies: 2, reposts: 6, likes: 41,
                    embed: .images([image]))
    }

    /// Every embed shape in one column, to find where spacing goes wrong.
    private var embedVariants: [FeedViewPost] {
        let wide = EmbedImage(thumb: nil, fullsize: nil, alt: "Breit",
                              aspectRatio: .init(width: 1600, height: 900))
        let tall = EmbedImage(thumb: nil, fullsize: nil, alt: "Hoch",
                              aspectRatio: .init(width: 900, height: 1600))
        let square = EmbedImage(thumb: nil, fullsize: nil, alt: nil,
                                aspectRatio: .init(width: 1000, height: 1000))
        let noRatio = EmbedImage(thumb: nil, fullsize: nil, alt: nil, aspectRatio: nil)

        let external = EmbedExternal(uri: "https://atproto.com/guides/glossary",
                                     title: "AT Protocol Glossary",
                                     description: "Die Begriffe, die im Protokoll vorkommen.",
                                     thumb: nil)
        let quoted = QuotedPost(uri: "at://did:plc:x/app.bsky.feed.post/1",
                                author: author("kim.bsky.social", "Kim"),
                                value: PostRecord(text: "Der zitierte Beitrag."))
        let video = EmbedVideo(cid: "bafy", playlist: "https://v.example/p.m3u8",
                               thumbnail: nil, alt: "Clip",
                               aspectRatio: .init(width: 1280, height: 720))

        let a = author("a.test", "Breites Bild")
        let b = author("b.test", "Hohes Bild")
        let c = author("c.test", "Zwei Bilder")
        let d = author("d.test", "Ohne Verhältnis")
        let e = author("e.test", "Link")
        let f = author("f.test", "Zitat")
        let g = author("g.test", "Video")
        let h = author("h.test", "Unbekannt")

        return [
            post(a, "16:9", minutesAgo: 1, replies: 0, reposts: 0, likes: 1, embed: .images([wide])),
            post(b, "9:16", minutesAgo: 2, replies: 0, reposts: 0, likes: 1, embed: .images([tall])),
            post(c, "Zwei", minutesAgo: 3, replies: 0, reposts: 0, likes: 1, embed: .images([square, wide])),
            post(d, "Ohne aspectRatio", minutesAgo: 4, replies: 0, reposts: 0, likes: 1, embed: .images([noRatio])),
            post(e, "Mit Link", minutesAgo: 5, replies: 0, reposts: 0, likes: 1, embed: .external(external)),
            post(f, "Mit Zitat", minutesAgo: 6, replies: 0, reposts: 0, likes: 1, embed: .record(.post(quoted))),
            post(g, "Mit Video", minutesAgo: 7, replies: 0, reposts: 0, likes: 1, embed: .video(video)),
            post(h, "Unbekannter Embed-Typ", minutesAgo: 8, replies: 0, reposts: 0, likes: 1, embed: .unsupported)
        ]
    }

    /// Conversations as the chat service returns them: members include the signed-in
    /// account, so the other side has to be picked out.
    private var sampleConvos: [Convo] {
        func convo(_ handle: String, _ name: String, _ text: String,
                   minutesAgo: Int, unread: Int) -> Convo {
            let sent = ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
            let json = """
            {"id":"convo-\(handle)","rev":"1",
             "members":[{"did":"did:plc:me","handle":"tester.test"},
                        {"did":"did:plc:\(handle)","handle":"\(handle)","displayName":"\(name)"}],
             "lastMessage":{"id":"m1","text":"\(text)","sentAt":"\(sent)",
                            "sender":{"did":"did:plc:\(handle)"}},
             "unreadCount":\(unread)}
            """
            return try! JSONDecoder().decode(Convo.self, from: Data(json.utf8))
        }

        return [
            convo("maria.dev", "Maria Lindqvist",
                  "Hast du den Firehose-Endpunkt schon ausprobiert?", minutesAgo: 6, unread: 2),
            convo("jay.bsky.team", "Jay",
                  "Klingt gut — schick mir den Link, wenn du so weit bist.", minutesAgo: 92, unread: 0),
            convo("anna.pds.example.com", "Anna Weiß",
                  "Migration lief durch. Elf Minuten, ohne Ausfall.", minutesAgo: 400, unread: 0)
        ]
    }

    private var sampleMessages: [ChatMessage] {
        func message(_ id: String, _ text: String, mine: Bool, minutesAgo: Int) -> ChatMessage {
            let sent = ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
            let json = """
            {"id":"\(id)","text":"\(text)","sentAt":"\(sent)",
             "sender":{"did":"\(mine ? "did:plc:me" : "did:plc:maria")"}}
            """
            return try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        }

        return [
            message("1", "Hast du den Firehose-Endpunkt schon ausprobiert?", mine: false, minutesAgo: 46),
            message("2", "Ja — läuft seit gestern. Rund 40 Records pro Sekunde.", mine: true, minutesAgo: 42),
            message("3", "Und die Zuordnung zu den Servern?", mine: false, minutesAgo: 38),
            message("4", "Über das DID-Dokument. Ist eine Stichprobe, aber sie trägt.", mine: true, minutesAgo: 12),
            message("5", "Schick mir das mal, wenn es steht.", mine: false, minutesAgo: 6)
        ]
    }

    /// A post that answers another one, as the feed delivers it.
    private var replyPost: FeedViewPost {
        let json = """
        {"post":{"uri":"at://did:plc:kim/app.bsky.feed.post/9","cid":"c",
          "author":{"did":"did:plc:kim","handle":"kim.bsky.social","displayName":"Kim Faber"},
          "record":{"text":"Genau das war auch mein Eindruck — vor allem beim Wechsel des Servers.",
                    "createdAt":"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-900)))",
                    "reply":{"root":{"uri":"at://did:plc:jay/app.bsky.feed.post/1","cid":"c"},
                             "parent":{"uri":"at://did:plc:jay/app.bsky.feed.post/1","cid":"c"}}},
          "replyCount":2,"repostCount":1,"likeCount":14,
          "indexedAt":"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-900)))"},
         "reply":{"parent":{"uri":"at://did:plc:jay/app.bsky.feed.post/1","cid":"c",
                            "author":{"did":"did:plc:jay","handle":"jay.bsky.team","displayName":"Jay"},
                            "record":{"text":"Ein offenes Protokoll heißt: Du kannst gehen."},
                            "indexedAt":"2026-08-29T00:00:00Z"}}}
        """
        return try! JSONDecoder().decode(FeedViewPost.self, from: Data(json.utf8))
    }

    private var sampleProfile: ActorProfile {
        ActorProfile(did: "did:plc:anna", handle: "anna.pds.example.com",
                     displayName: "Anna Weiß", avatar: nil, banner: nil,
                     description: "Baut an dezentralen Netzen. Eigener PDS seit 2026. Mehr auf anna.example.com",
                     followersCount: 1284, followsCount: 342, postsCount: 2107, viewer: nil)
    }

    // MARK: - Rendering

    /// The renderer hands back the platform's own image type, and only macOS
    /// needs a trip through a bitmap representation to reach PNG.
    private func png(from renderer: ImageRenderer<some View>) -> Data? {
        #if os(iOS)
        return renderer.uiImage?.pngData()
        #else
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }

    /// Every setting a picture depends on is pinned and handed back — see
    /// `SnapshotSettings`. This helper used to set the theme and the language
    /// and leave them set, so running the tests on a Mac that also runs the app
    /// changed the app for its owner.
    private func render(_ view: some View, named name: String, height: CGFloat,
                        textScale: CGFloat = 1.0, theme: AppTheme = .dark,
                        language: AppLanguage = .en, online: Bool = true) throws {
        try SnapshotSettings.pinned(theme: theme, language: language) { settings in
            try draw(view, named: name, height: height, textScale: textScale,
                     settings: settings, online: online)
        }
    }

    private func draw(_ view: some View, named name: String, height: CGFloat,
                      textScale: CGFloat, settings: AppSettings, online: Bool) throws {
        let model = AppModel()
        let reachability = Reachability()
        reachability.setOnlineForTesting(online)
        Theme.Font.dynamicScale = textScale

        let wrapped = view
            .environment(model)
            .environment(settings)
            .environment(reachability)
            .frame(width: 393, height: height)
            .background(Theme.Palette.background)

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 3

        guard let data = png(from: renderer) else {
            Issue.record("renderer produced no image for \(name)")
            return
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        Theme.Font.dynamicScale = 1.0
    }

    @Test("Feed renders")
    func feed() throws {
        // A lazy stack stays empty inside a renderer — it never gets a viewport to
        // measure against — so the rows are laid out eagerly here. The row view
        // itself is the real one.
        let posts = [samplePosts[0], replyPost, postWithImage, samplePosts[4]]
        let view = VStack(spacing: 0) {
            ScreenHeader(title: "Relays")
            ForEach(posts) { item in
                PostRowView(post: item.post,
                            repostedBy: nil,
                            replyingTo: item.reply?.parent?.author)
                Hairline()
            }
            Spacer(minLength: 0)
        }
        try render(view, named: "snapshot-feed", height: 780)
    }

    /// More than half of a busy account's main tab is reposts, so the profile
    /// snapshot has to contain one — otherwise it shows the easy half.
    private func reposted(_ item: FeedViewPost, by who: ActorProfile) -> FeedViewPost {
        FeedViewPost(post: item.post, reply: nil,
                     reason: .repost(by: who, indexedAt: item.post.indexedAt))
    }

    @Test("Profile renders")
    func profile() throws {
        let owner = sampleProfile
        let posts = [samplePosts[0],
                     reposted(samplePosts[1], by: owner),
                     samplePosts[2]]
        let view = VStack(spacing: 0) {
            ScreenHeader(title: owner.handle, showsBack: true)
            ProfileHeader(profile: owner, actor: owner.did)
            Hairline()
            ForEach(posts) { item in
                // The screen's own row, not a hand-built one — the bug this
                // replaces was a call site that had drifted from it.
                FeedRow(item: item)
                Hairline()
            }
            Spacer(minLength: 0)
        }
        try render(view, named: "snapshot-profile", height: 900)
    }

    @Test("Messages list renders")
    func messages() throws {
        let convos = sampleConvos
        let view = VStack(spacing: 0) {
            ScreenHeader(title: L(.tabMessages))
            ForEach(convos) { convo in
                ConversationRow(convo: convo, mine: "did:plc:me")
                Hairline(inset: Theme.Metric.hPadding)
            }
            Spacer(minLength: 0)
        }
        try render(view, named: "snapshot-messages", height: 560)
    }

    /// The screens whose text was hardest to keep in step, in both languages at
    /// the size they are actually read at.
    @Test("Both languages render", arguments: [AppLanguage.en, .de])
    func languages(_ language: AppLanguage) throws {
        L10n.language = language

        let view = VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: L(.tabMessages))
            ForEach(sampleConvos) { convo in
                ConversationRow(convo: convo, mine: "did:plc:me")
                Hairline(inset: Theme.Metric.hPadding)
            }

            VStack(alignment: .leading, spacing: 14) {
                RelaySectionTitle(text: L(.relayThroughput))
                HStack(spacing: 12) {
                    RelayReading(label: L(.relayLatency), value: "412 ms",
                                 note: L(.relayLatencyHint))
                    RelayReading(label: L(.relaySeen), value: Format.grouped(18402))
                }
                RelayShareBar(label: L(.radarFollows), count: 780, total: 9800)

                SettingsRow(label: L(.relayPulse), detail: L(.relayPulseHint)) {
                    Text(L(.settingsLanguageSystem))
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                // The follow button's two visible states and what a tap on the
                // second one is announced as.
                HStack(spacing: 14) {
                    Text(L(.follow))
                    Text(L(.unfollow))
                    Text(L(.unfollowAction))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                Text(L(.errorChatNotPermitted))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.top, 20)

            Spacer(minLength: 0)
        }

        try render(view, named: "language-\(language.rawValue)", height: 720,
                   language: language)
        L10n.language = .en
    }

    /// The four states a moderated post can be in, next to each other, so the
    /// difference between "covered" and "gone" is visible at a glance.
    @Test("Moderation states render")
    func moderation() throws {
        let warned = ModerationDecision(verdict: .warn, reason: L(.labelWarned),
                                        source: .selfLabel("!warn"), labels: ["!warn"])
        let covered = ModerationDecision(verdict: .blurContent, reason: L(.labelHidden),
                                         source: .labeler(did: "did:plc:l", label: "!hide"),
                                         labels: ["!hide"])
        let media = ModerationDecision(verdict: .blurMedia, reason: L(.labelNudity),
                                       source: .labeler(did: "did:plc:l", label: "nudity"),
                                       labels: ["nudity"])

        let view = VStack(alignment: .leading, spacing: 18) {
            RelaySectionTitle(text: L(.settingsModeration))

            ModerationNotice(decision: warned, uri: "at://a/1")
            ModerationNotice(decision: covered, uri: "at://a/2")

            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                        .fill(Theme.Palette.surfaceRaised)
                }
                .modifier(MediaCover(decision: media, uri: "at://a/3"))

            ModerationGap(reason: L(.moderationBlockedBy))
            ModerationGap(reason: L(.moderationViaList, "Bots"))
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 20)

        try render(view, named: "moderation-states", height: 560)
    }

    @Test("The labeler screen renders")
    func labelers() throws {
        let payload = """
        {"views":[{
          "uri":"at://did:plc:mod/app.bsky.labeler.service/self",
          "creator":{"did":"did:plc:mod","handle":"moderation.example",
                     "displayName":"Moderation Service","associated":{"labeler":true}},
          "policies":{"labelValues":["spam","scam","rumor","!hide"],
            "labelValueDefinitions":[
              {"identifier":"spam","severity":"inform","blurs":"content","defaultSetting":"hide",
               "locales":[{"lang":"en","name":"Spam","description":"Unwanted, repeated, or unrelated actions."}]},
              {"identifier":"scam","severity":"alert","blurs":"content","defaultSetting":"hide",
               "locales":[{"lang":"en","name":"Scam","description":"Scams, phishing & fraud."}]}]}
        }]}
        """
        struct Response: Decodable { let views: [LabelerService] }
        let service = try JSONDecoder().decode(Response.self, from: Data(payload.utf8)).views[0]

        let candidate = ActorProfile(did: "did:plc:x", handle: "arttheft.example",
                                     displayName: "Art Theft Watch", avatar: nil, banner: nil,
                                     description: nil, followersCount: nil, followsCount: nil,
                                     postsCount: nil, viewer: nil, verification: nil,
                                     labels: nil, associated: AssociatedState(labeler: true))

        let view = VStack(alignment: .leading, spacing: 22) {
            Text(L(.labelersHint))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            RelaySectionTitle(text: L(.labelersTitle))
            LabelerCard(service: service, startsExpanded: true)

            VStack(alignment: .leading, spacing: 10) {
                RelaySectionTitle(text: L(.labelersSearch))
                LabelerResultRow(profile: candidate)
            }

            VStack(alignment: .leading, spacing: 8) {
                RelaySectionTitle(text: L(.labelersApplied))
                Text(L(.labelersAppliedHint))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Bluesky Moderation Service")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 20)

        try render(view, named: "labelers", height: 620)
    }

    @Test("Muted words and lists render")
    func wordsAndLists() throws {
        let list = ListView(uri: "at://did:plc:x/app.bsky.graph.list/1",
                            name: "Content Scrapers", description: "Accounts that repost art without credit.",
                            avatar: nil, purpose: "app.bsky.graph.defs#modlist",
                            listItemCount: 777, creator: nil, viewer: nil)

        let view = VStack(alignment: .leading, spacing: 22) {
            RelaySectionTitle(text: L(.mutedWordsTitle))
            MutedWordRow(word: MutedWord(value: "season finale", targets: [.content, .tag],
                                         expiresAt: Date().addingTimeInterval(6 * 86_400)))
            Hairline()
            MutedWordRow(word: MutedWord(value: "crypto", targets: [.tag],
                                         scope: .excludeFollowing))
            Hairline()

            HStack(spacing: 8) {
                Toggle(isOn: .constant(true)) { Text(L(.mutedWordText)) }
                    .toggleStyle(ChipToggleStyle())
                Toggle(isOn: .constant(false)) { Text(L(.mutedWordTag)) }
                    .toggleStyle(ChipToggleStyle())
                Spacer(minLength: 0)
            }

            RelaySectionTitle(text: L(.listsSubscribed))
            ListCard(list: list)
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 20)

        try render(view, named: "words-and-lists", height: 480)
    }

    @Test("A post's own rules render")
    func ownSpace() throws {
        let author = author("maria.dev", "Maria Lindqvist")
        let limited = post(author, "Antworten habe ich hier eingeschränkt.", minutesAgo: 4,
                           replies: 2, reposts: 0, likes: 9)

        let view = VStack(alignment: .leading, spacing: 0) {
            PostRowView(post: limited.post)
            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                RelaySectionTitle(text: L(.replyWho))
                ForEach(ReplyRule.offered) { rule in
                    Text(rule.label)
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(rule == .followed
                                         ? Theme.Palette.accent : Theme.Palette.textSecondary)
                }
                Text(ThreadGate(rules: [.followed]).summary ?? "")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(ThreadGate(rules: []).summary ?? "")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 18)

            ModerationGap(reason: L(.replyHidden))
            Hairline()
            ModerationGap(reason: L(.hiddenPostNotice))
        }

        try render(view, named: "own-space", height: 520)
    }

    @Test("Message rules and a muted conversation render")
    func messageModeration() throws {
        let sent = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let json = """
        {"id":"convo-1","rev":"1",
         "members":[{"did":"did:plc:me","handle":"tester.test"},
                    {"did":"did:plc:x","handle":"noisy.example","displayName":"Noisy Account"}],
         "lastMessage":{"id":"m1","text":"Dritte Nachricht heute.","sentAt":"\(sent)",
                        "sender":{"did":"did:plc:x"}},
         "unreadCount":3,"muted":true}
        """
        let muted = try JSONDecoder().decode(Convo.self, from: Data(json.utf8))

        let view = VStack(alignment: .leading, spacing: 0) {
            ConversationRow(convo: muted, mine: "did:plc:me")
            Hairline(inset: Theme.Metric.hPadding)

            VStack(alignment: .leading, spacing: 14) {
                RelaySectionTitle(text: L(.messagesWho))
                HStack(spacing: 10) {
                    ForEach(MessageRule.allCases) { rule in
                        Text(rule.label)
                            .font(Theme.Font.ui(13, .medium))
                            .foregroundStyle(rule == .following
                                             ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(rule == .following
                                                       ? Theme.Palette.accent
                                                       : Theme.Palette.surface))
                    }
                }

                RelaySectionTitle(text: L(.reportTo))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(.reportToDefault))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("Bluesky Moderation Service")
                        .foregroundStyle(Theme.Palette.accent)
                    Text("Art Theft Watch")
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .font(Theme.Font.mono(12))

                Text(L(.convoLeaveQuestion))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 20)
        }

        try render(view, named: "message-moderation", height: 430)
    }


    /// Every settings row whose control is a set of choices, at the size and in
    /// the language where the words are longest. These are the rows that used to
    /// wrap at the small size and truncate at the large one.
    @Test("Choice rows survive every text size",
          arguments: [TextSizeOption.small, .medium, .large])
    func choiceRows(_ size: TextSizeOption) throws {
        L10n.language = .de

        let view = VStack(spacing: 0) {
            SettingsRow(label: L(.messagesWho), stacked: true) {
                MonoSegment(selection: .constant(MessageRule.following),
                            options: MessageRule.allCases, label: \.label, fills: true)
            }
            Hairline(inset: Theme.Metric.hPadding)
            SettingsRow(label: L(.settingsTheme), stacked: true) {
                MonoSegment(selection: .constant(AppTheme.dark),
                            options: AppTheme.allCases, label: \.label, fills: true)
            }
            Hairline(inset: Theme.Metric.hPadding)
            SettingsRow(label: L(.labelNudity), stacked: true) {
                MonoSegment(selection: .constant(LabelVisibility.warn),
                            options: LabelVisibility.allCases, label: \.label, fills: true)
            }
            Hairline(inset: Theme.Metric.hPadding)
            SettingsRow(label: L(.settingsLanguage), stacked: true) {
                MonoSegment(selection: .constant(AppLanguage.de),
                            options: AppLanguage.allCases, label: \.label, fills: true)
            }
            Spacer(minLength: 0)
        }

        try render(view, named: "row-choices-\(size.rawValue)", height: 460,
                   textScale: size.scale, language: .de)
        L10n.language = .en
    }

    @Test("A quote renders, with and without a picture")
    func quotes() throws {
        let jay = author("jay.bsky.team", "Jay")
        let maria = author("maria.dev", "Maria Lindqvist")

        let quoted = QuotedPost(
            uri: "at://did:plc:m/app.bsky.feed.post/1",
            author: maria,
            value: PostRecord(text: "Der Server steht im DID-Dokument — das ist das Schöne daran."))

        let image = EmbedImage(thumb: nil, fullsize: nil, alt: "ein Bild",
                               aspectRatio: .init(width: 1200, height: 800))

        var plain = post(jay, "Genau das.", minutesAgo: 3, replies: 1, reposts: 2, likes: 12)
        plain = FeedViewPost(post: PostView(uri: plain.post.uri, cid: plain.post.cid,
                                            author: jay, record: plain.post.record,
                                            embed: .record(.post(quoted)), replyCount: 1,
                                            repostCount: 2, likeCount: 12, quoteCount: 4,
                                            indexedAt: plain.post.indexedAt, viewer: nil,
                                            labels: nil),
                             reply: nil, reason: nil)

        var withPicture = post(jay, "Und hier das Bild dazu.", minutesAgo: 9,
                               replies: 0, reposts: 0, likes: 3)
        withPicture = FeedViewPost(post: PostView(uri: withPicture.post.uri + "-2",
                                                  cid: withPicture.post.cid, author: jay,
                                                  record: withPicture.post.record,
                                                  embed: .recordWithMedia(media: .images([image]),
                                                                          record: .post(quoted)),
                                                  replyCount: 0, repostCount: 0, likeCount: 3,
                                                  quoteCount: 0,
                                                  indexedAt: withPicture.post.indexedAt,
                                                  viewer: nil, labels: nil),
                                   reply: nil, reason: nil)

        let view = VStack(spacing: 0) {
            PostRowView(post: plain.post)
            Hairline()
            PostRowView(post: withPicture.post)
            Spacer(minLength: 0)
        }

        try render(view, named: "quotes", height: 620)
    }

    /// The sign-in screen on each of the four grounds. The traces behind it are
    /// drawn from the theme, so this is the only way to see that they stay faint
    /// on a light ground and readable on a blue one.
    @Test("The sign-in backdrop works on every ground",
          arguments: [AppTheme.dark, .dim, .light, .blue])
    func loginBackdrop(_ theme: AppTheme) throws {
        try render(AuthGateView(showsLogin: true), named: "login-\(theme.rawValue)",
                   height: 760, theme: theme)
    }

    @Test("The offline line says what is wrong, in both languages",
          arguments: [AppLanguage.en, .de])
    func offlineNotice(_ language: AppLanguage) throws {
        L10n.language = language

        let view = VStack(spacing: 0) {
            ScreenHeader(title: "Relays")
            OfflineNotice()
            Hairline()
            StateMessage(text: L(.errorOffline), systemImage: "wifi.slash")
            Spacer(minLength: 0)
        }

        try render(view, named: "offline-\(language.rawValue)", height: 320,
                   language: language, online: false)
        L10n.language = .en
    }

    /// The search screen before anything is typed. It used to be a sentence on
    /// an empty screen.
    @Test("Discovery fills the empty search screen")
    func discovery() throws {
        let feeds = [
            FeedGeneratorView(uri: "at://did:plc:a/app.bsky.feed.generator/for-you",
                              displayName: "For You",
                              description: "A personalised feed built from what you like.",
                              avatar: nil, likeCount: 52657),
            FeedGeneratorView(uri: "at://did:plc:b/app.bsky.feed.generator/quiet",
                              displayName: "Quiet Posters",
                              description: "People who post rarely, surfaced when they do.",
                              avatar: nil, likeCount: 1840),
        ]

        let view = VStack(alignment: .leading, spacing: 20) {
            RelaySectionTitle(text: L(.discoverFeeds))
            ForEach(feeds) { feed in DiscoverFeedRow(feed: feed) }

            RelaySectionTitle(text: L(.discoverPeople))
            ForEach([author("maria.dev", "Maria Lindqvist", followers: 2100),
                     author("jay.bsky.team", "Jay", followers: 90000)]) { profile in
                HStack(spacing: Theme.Metric.avatarGap) {
                    AvatarView(url: nil, seed: profile.handle, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .font(Theme.Font.ui(15, .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("@\(profile.handle)")
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 20)

        try render(view, named: "discover", height: 520)
    }

    @Test("One conversation renders")
    func conversation() throws {
        let messages = sampleMessages
        let view = VStack(spacing: 0) {
            ScreenHeader(title: L(.tabMessages), showsBack: true)
            VStack(spacing: 8) {
                ForEach(messages) { message in
                    MessageBubble(message: message, mine: message.isMine("did:plc:me"))
                }
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 14)
            Spacer(minLength: 0)
            MessageComposer(draft: .constant(""), isSending: false, onSend: {})
        }
        try render(view, named: "snapshot-conversation", height: 620)
    }

    @Test("Launch and sign-in render")
    func authGate() throws {
        // The launch screen centres its wordmark; the form sits above centre.
        try render(AuthGateView(showsLogin: false), named: "snapshot-splash", height: 700)
        try render(AuthGateView(showsLogin: true), named: "snapshot-signin", height: 700)
    }

    @Test("Compose button renders")
    func composeButton() throws {
        try render(ComposeButton {}.padding(20), named: "snapshot-compose-button", height: 94)
    }

    /// The badge takes the accent colour, which differs per ground. Rendering the
    /// same header on two of them shows whether it holds on both.
    @Test("Verification badge renders on every ground")
    func verification() throws {
        let verified = ActorProfile(
            did: "did:plc:anna", handle: "anna.pds.example.com", displayName: "Anna Weiß",
            avatar: nil, banner: nil,
            description: "Baut an dezentralen Netzen. Eigener PDS seit 2026.",
            followersCount: 1284, followsCount: 342, postsCount: 2107, viewer: nil,
            verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "none"))

        let verifier = ActorProfile(
            did: "did:plc:org", handle: "presse.example.org", displayName: "Redaktion",
            avatar: nil, banner: nil, description: "Verifiziert Konten unserer Redaktion.",
            followersCount: 24800, followsCount: 91, postsCount: 5310, viewer: nil,
            verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "valid"))

        for (theme, name) in [(AppTheme.dark, "dark"), (.blue, "blue"), (.light, "light")] {
            let view = VStack(spacing: 0) {
                ProfileHeader(profile: verified, actor: verified.did)
                Hairline()
                ProfileHeader(profile: verifier, actor: verifier.did)
                Spacer(minLength: 0)
            }
            try render(view, named: "snapshot-verified-\(name)", height: 640, theme: theme)
        }
    }

    /// The same feed at the largest text the app allows, to see what breaks when
    /// someone turns the system size up.

    // MARK: - Relay

    /// A minute of throughput with the shape the real stream has: never silent,
    /// never flat.
    private var sampleBuckets: [Int] {
        (0..<RelayMonitor.window).map { index in
            // A lull around the twenties and a burst near the end, so both ends
            // of the mapping are visible in one picture.
            let wave = sin(Double(index) / 6.0) + sin(Double(index) / 2.3) * 0.35
            let lull = index > 18 && index < 27 ? 0.35 : 1.0
            let burst = index > 48 ? 1.5 : 1.0
            return max(0, Int((30 + wave * 9) * lull * burst))
        }
    }

    private func relayEvent(_ kind: RadarEvent.Kind, _ text: String,
                            media: Bool = false) -> RadarEvent {
        RadarEvent(did: "did:plc:\(UUID().uuidString.prefix(12).lowercased())",
                   rkey: "3kabc", cid: "bafy", kind: kind, text: text,
                   subject: kind == .post ? nil : "at://did:plc:b/app.bsky.feed.post/1",
                   langs: ["en"], hasMedia: media, createdAt: nil, receivedAt: Date())
    }

    @Test("The pulse sits exactly on the hairline it replaces")
    func relayHeader() throws {
        let header = VStack(spacing: 0) {
            ScreenHeader(title: "Relays", titleAction: {}) {
                HStack(spacing: 20) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            .overlay(alignment: .bottom) {
                RelayPulse(buckets: sampleBuckets)
            }

            // The same header with an idle stream, which has to be indistinguishable
            // from a plain hairline.
            ScreenHeader(title: "Relays", titleAction: {}) { EmptyView() }
                .overlay(alignment: .bottom) {
                    RelayPulse(buckets: Array(repeating: 0, count: RelayMonitor.window))
                }

            Spacer()
        }

        try render(header, named: "relay-header", height: 140)
    }

    @Test("The readings render")
    func relayReadings() throws {
        let readings = VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Circle().fill(Theme.Palette.repost).frame(width: 7, height: 7)
                Text("Live").font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("us-east-2").font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RelayView.rate(37.4))
                        .font(Theme.Font.mono(34, .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(L(.relayPerSecond))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                RelayPulse(buckets: sampleBuckets, style: .bars, height: 56)
            }

            HStack(alignment: .top, spacing: 12) {
                RelayReading(label: L(.relayLatency), value: "412 ms",
                             note: L(.relayLatencyHint))
                RelayReading(label: L(.relaySeen), value: Format.grouped(18402))
            }

            VStack(alignment: .leading, spacing: 9) {
                RelaySectionTitle(text: L(.relayComposition))
                RelayShareBar(label: L(.radarPosts), count: 2140, total: 9800)
                RelayShareBar(label: L(.radarLikes), count: 5900, total: 9800)
                RelayShareBar(label: L(.radarReposts), count: 980, total: 9800)
                RelayShareBar(label: L(.radarFollows), count: 780, total: 9800)
            }

            VStack(alignment: .leading, spacing: 9) {
                RelaySectionTitle(text: L(.relayServers))
                RelayShareBar(label: "bsky.social", count: 186, total: 214)
                RelayShareBar(label: "pds.example.com", count: 17, total: 214)
                RelayShareBar(label: "blueskyweb.xyz", count: 11, total: 214)
                HStack(spacing: 6) {
                    Text(L(.relaySample, 214))
                    Text("·")
                    Text("13 % \(L(.relaySelfHosted))")
                }
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 0) {
                RelaySectionTitle(text: L(.relayLatest))
                    .padding(.bottom, 9)
                RelayEventRow(event: relayEvent(.post, "the network is writing this right now"))
                Hairline()
                RelayEventRow(event: relayEvent(.like, ""))
                Hairline()
                RelayEventRow(event: relayEvent(.post, "a post with a picture attached", media: true))
                Hairline()
                RelayEventRow(event: relayEvent(.follow, ""))
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 20)

        try render(readings, named: "relay-readings", height: 940)
    }

    @Test("Feed survives the largest text size")
    func feedAtLargeText() throws {
        let posts = Array(samplePosts.prefix(3))
        let view = VStack(spacing: 0) {
            ScreenHeader(title: "Relays")
            ForEach(posts) { item in
                PostRowView(post: item.post)
                Hairline()
            }
            Spacer(minLength: 0)
        }
        try render(view, named: "snapshot-feed-large", height: 780, textScale: 1.45)
    }
}
