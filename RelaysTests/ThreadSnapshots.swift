//
//  ThreadSnapshots.swift
//  RelaysTests
//
//  `ThreadView` fetches before it draws, and its `LazyVStack` stays empty
//  inside a renderer, so what is composed here is the same arrangement it
//  builds: the chain above, the opened post on its own ground, the answers
//  indented under it. The rows are the real `PostRowView`.
//

import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import Relays

@MainActor
@Suite("Thread")
struct ThreadSnapshots {

    /// The arrangement `ThreadView` builds, composed eagerly.
    private var conversation: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.titleThread), showsBack: true)

            ForEach(ThreadFixture.ancestors) { ancestor in
                PostRowView(post: ancestor)
                Hairline()
            }

            PostRowView(post: ThreadFixture.focused, isDetail: true)
                .background(Theme.Palette.surface.opacity(0.35))
            Hairline()

            ForEach(ThreadFixture.replies) { reply in
                PostRowView(post: reply, threadRoot: ThreadFixture.focused)
                    .padding(.leading, 8)
                Hairline(inset: 8)
            }

            Spacer(minLength: 0)
        }
    }

    @Test("Six accounts, one conversation", arguments: [AppLanguage.de, .en])
    func thread(_ language: AppLanguage) throws {
        try write(conversation, named: "snapshot-thread-\(language == .de ? "de" : "en")",
                  width: 393, height: 1500, language: language)
    }

    /// The same conversation at the width a Mac window opens at, so the two can
    /// be held next to each other.
    @Test("It holds together in a Mac window")
    func macWidth() throws {
        try write(conversation, named: "snapshot-thread-mac", width: 480, height: 1400)
    }

    private func write(_ view: some View, named name: String,
                       width: CGFloat, height: CGFloat,
                       language: AppLanguage = .de) throws {
        try SnapshotSettings.pinned(language: language) { settings in
            try draw(view, named: name, width: width, height: height, settings: settings)
        }
    }

    private func draw(_ view: some View, named name: String,
                      width: CGFloat, height: CGFloat,
                      settings: AppSettings) throws {
        let wrapped = view
            .environment(AppModel())
            .environment(settings)
            .environment(Reachability())
            .frame(width: width, height: height)
            .background(Theme.Palette.background)

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2

        #if os(iOS)
        let data = renderer.uiImage?.pngData()
        #else
        let data = renderer.nsImage
            .flatMap(\.tiffRepresentation)
            .flatMap(NSBitmapImageRep.init(data:))
            .flatMap { $0.representation(using: .png, properties: [:]) }
        #endif

        let png = try #require(data, "renderer produced no image for \(name)")
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@MainActor
@Suite("App passwords")
struct AppPasswordSnapshots {

    @Test("The register, with the thing it cannot know said out loud",
          arguments: [AppLanguage.de, .en])
    func passwords(_ language: AppLanguage) throws {
        let entries = [
            AppPassword(name: "Relays", createdAt: "2026-08-29T09:23:28.000Z", privileged: true),
            AppPassword(name: "Old phone", createdAt: "2026-01-02T10:00:00.000Z", privileged: nil),
            AppPassword(name: "Graysky", createdAt: "2025-11-14T18:40:00.000Z", privileged: false)
        ]

        try SnapshotSettings.pinned(language: language) { settings in
            let view = VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L(.appPasswordsTitle))
                VStack(alignment: .leading, spacing: 16) {
                    Text(L(.appPasswordsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(L(.appPasswordsWarning), systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .font(Theme.Font.ui(13, .medium))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                HStack(spacing: 8) {
                                    Text(L(.appPasswordCreated,
                                           RelativeTime.short(entry.createdAt)))
                                        .font(Theme.Font.mono(10))
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                    if entry.canUseMessages {
                                        Text(L(.appPasswordMessages))
                                            .font(Theme.Font.mono(10))
                                            .foregroundStyle(Theme.Palette.accent)
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            Text(L(.appPasswordRevoke))
                                .font(Theme.Font.ui(12))
                                .foregroundStyle(Theme.Palette.danger)
                        }
                        .padding(.vertical, 8)
                        Hairline()
                    }
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
                Spacer(minLength: 0)
            }
            .environment(AppModel())
            .environment(settings)
            .environment(Reachability())
            .frame(width: 393, height: 560)
            .background(Theme.Palette.background)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            #if os(iOS)
            let data = renderer.uiImage?.pngData()
            #else
            let data = renderer.nsImage.flatMap(\.tiffRepresentation)
                .flatMap(NSBitmapImageRep.init(data:))
                .flatMap { $0.representation(using: .png, properties: [:]) }
            #endif
            let png = try #require(data)
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try png.write(to: dir.appendingPathComponent(
                "snapshot-passwords-\(language == .de ? "de" : "en").png"))
        }
    }
}

@MainActor
@Suite("What reaches you")
struct NotificationKindsSnapshots {

    /// Twelve kinds and an audience. Drawn eagerly: the screen's own body is a
    /// ScrollView, which an ImageRenderer leaves empty.
    @Test("The account's notification settings", arguments: [AppLanguage.de, .en])
    func kinds(_ language: AppLanguage) throws {
        let app = AppModel()
        let rows: [NotificationPreferences.Kind] = [.reply, .mention, .quote, .like, .repost]

        try SnapshotSettings.pinned(language: language) { settings in
            let view = VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: L(.notifyKinds))
                VStack(alignment: .leading, spacing: 22) {
                    Text(L(.notifyKindsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        RelaySectionTitle(text: L(.notifyAudience))
                        MonoSegment(selection: .constant(NotificationPreferences.Audience.all),
                                    options: NotificationPreferences.Audience.allCases,
                                    label: \.label, fills: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        RelaySectionTitle(text: L(.notifyGroupPosts))
                        ForEach(rows) { kind in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NotificationKindsView.label(for: kind))
                                    .font(Theme.Font.ui(13))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                MonoSegment(selection: .constant(NotificationKindsView.Level.alert),
                                            options: NotificationKindsView.Level.allCases,
                                            label: \.label, fills: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                Spacer(minLength: 0)
            }
            .environment(app)
            .environment(settings)
            .environment(Reachability())
            .frame(width: 393, height: 700)
            .background(Theme.Palette.background)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            #if os(iOS)
            let data = renderer.uiImage?.pngData()
            #else
            let data = renderer.nsImage.flatMap(\.tiffRepresentation)
                .flatMap(NSBitmapImageRep.init(data:))
                .flatMap { $0.representation(using: .png, properties: [:]) }
            #endif
            let png = try #require(data)
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try png.write(to: dir.appendingPathComponent(
                "snapshot-notify-\(language == .de ? "de" : "en").png"))
        }
    }
}

@MainActor
@Suite("The sign-in line")
struct HomeServerLineSnapshots {

    /// Real hosts and real numbers, read off the live relay: pfrazee.com sits on
    /// one of Bluesky's machines, rudyfraser.com does not.
    @Test("What the line says, in every state", arguments: [AppLanguage.de, .en])
    func states(_ language: AppLanguage) throws {
        let states: [HomeServerLookup.State] = [
            .looking,
            .found(host: "morel.us-east.host.bsky.network",
                   status: RelayHost(hostname: "morel.us-east.host.bsky.network",
                                     seq: nil, accountCount: 211_154, status: "active")),
            .found(host: "blacksky.app",
                   status: RelayHost(hostname: "blacksky.app", seq: nil,
                                     accountCount: 40_773, status: "active")),
            .found(host: "pds.example.com", status: nil),
            .unknown
        ]

        let view = VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                HomeServerLine(state: state)
            }
        }
        .padding(20)

        try SnapshotSettings.pinned(language: language) { settings in
            let wrapped = view
                .environment(AppModel())
                .environment(settings)
                .environment(Reachability())
                .frame(width: 393, height: 190)
                .background(Theme.Palette.background)

            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = 3
            #if os(iOS)
            let data = renderer.uiImage?.pngData()
            #else
            let data = renderer.nsImage.flatMap(\.tiffRepresentation)
                .flatMap(NSBitmapImageRep.init(data:))
                .flatMap { $0.representation(using: .png, properties: [:]) }
            #endif
            let png = try #require(data)
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try png.write(to: dir.appendingPathComponent(
                "snapshot-signin-line-\(language == .de ? "de" : "en").png"))
        }
    }
}

@MainActor
@Suite("Server register")
struct HostRegisterSnapshots {

    private func host(_ name: String, _ accounts: Int, _ status: String) -> RelayHost {
        RelayHost(hostname: name, seq: nil, accountCount: accounts, status: status)
    }

    /// Real names and real numbers, taken off the live relay, so the picture is
    /// of the network rather than of invented data.
    @Test("The register, with the totals it exists for", arguments: [AppLanguage.de, .en])
    func register(_ language: AppLanguage) throws {
        let model = HostsModel()
        model.applyForTesting([
            host("porcini.us-east.host.bsky.network", 215_409, "active"),
            host("atproto.brid.gy", 63_451, "active"),
            host("bbi.to", 42_602, "offline"),
            host("blacksky.app", 40_772, "active"),
            host("pds.wsocial.network", 32_290, "active"),
            host("eurosky.social", 30_755, "active"),
            host("wallets.tz2at.store", 22_699, "offline"),
            host("pds.federdeck.com", 19_284, "offline"),
            host("certified.one", 14_633, "active"),
            host("quiet.example.com", 402, "idle"),
            host("banned.example.com", 88, "banned")
        ])

        try SnapshotSettings.pinned(language: language) { settings in
            // Composed eagerly: the screen's own list is a LazyVStack, which
            // draws nothing inside a renderer.
            let view = VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L(.hostsTitle))
                HostTotalsView(totals: model.totals)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.vertical, 18)
                Hairline()
                ForEach(model.matches(query: "", status: nil).prefix(9)) { host in
                    HostRow(host: host)
                    Hairline(inset: Theme.Metric.hPadding)
                }
                Spacer(minLength: 0)
            }
                .environment(AppModel())
                .environment(settings)
                .environment(Reachability())
                .frame(width: 393, height: 900)
                .background(Theme.Palette.background)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            #if os(iOS)
            let data = renderer.uiImage?.pngData()
            #else
            let data = renderer.nsImage.flatMap(\.tiffRepresentation)
                .flatMap(NSBitmapImageRep.init(data:))
                .flatMap { $0.representation(using: .png, properties: [:]) }
            #endif
            let png = try #require(data)
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try png.write(to: dir.appendingPathComponent(
                "snapshot-hosts-\(language == .de ? "de" : "en").png"))
        }
    }
}

@MainActor
@Suite("Embedded record cards")
struct EmbedCardSnapshots {

    private func author(_ handle: String, _ name: String) -> ActorProfile {
        ActorProfile(did: "did:plc:\(handle.prefix(6))", handle: handle, displayName: name,
                     avatar: nil, banner: nil, description: nil, followersCount: nil,
                     followsCount: nil, postsCount: nil, viewer: nil)
    }

    private func post(_ text: String, _ embed: PostEmbed) -> PostView {
        PostView(uri: "at://did:plc:me/app.bsky.feed.post/\(abs(text.hashValue) % 9999)",
                 cid: "bafy", author: author("anna.pds.example.com", "Anna Weiß"),
                 record: PostRecord(text: text, createdAt: ISO8601DateFormatter().string(from: Date()),
                                    facets: nil),
                 embed: embed, replyCount: 0, repostCount: 0, likeCount: 0, quoteCount: nil,
                 indexedAt: ISO8601DateFormatter().string(from: Date()), viewer: nil, labels: nil)
    }

    /// Seven of these drew nothing at all before, and the deleted one drew an
    /// empty bordered box.
    @Test("All seven that used to be blank", arguments: [AppLanguage.de, .en])
    func cards(_ language: AppLanguage) throws {
        let emily = author("emily.space", "Emily Hunt")
        let rows: [PostView] = [
            post("Ein Feed", .record(.feed(EmbeddedFeed(
                uri: "at://a/app.bsky.feed.generator/astro", displayName: "Astronomy",
                description: "Astronomy posts, from astronomers!", likeCount: 9027, creator: emily)))),
            post("Eine Liste", .record(.list(EmbeddedList(
                uri: "at://a/app.bsky.graph.list/1", name: "Astronomers",
                description: "People who look up", listItemCount: 240, creator: emily)))),
            post("Ein Starter Pack", .record(.starterPack(EmbeddedStarterPack(
                uri: "at://a/app.bsky.graph.starterpack/1", joinedAllTimeCount: 17,
                creator: emily,
                record: .init(name: "NFL Conference Championships",
                              description: "Football posters"))))),
            post("Ein Moderationsdienst", .record(.labeler(EmbeddedLabeler(
                uri: "at://a/app.bsky.labeler.service/self", likeCount: 1200,
                creator: author("moderation.bsky.app", "Bluesky Moderation"))))),
            post("Gelöscht", .record(.notFound)),
            post("Blockiert", .record(.blocked(did: "did:plc:b"))),
            post("Gelöst", .record(.detached))
        ]

        let view = VStack(spacing: 0) {
            ForEach(rows) { row in
                PostRowView(post: row)
                Hairline()
            }
            Spacer(minLength: 0)
        }

        try SnapshotSettings.pinned(language: language) { settings in
            let wrapped = view
                .environment(AppModel())
                .environment(settings)
                .environment(Reachability())
                .frame(width: 393, height: 1180)
                .background(Theme.Palette.background)

            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = 2
            #if os(iOS)
            let data = renderer.uiImage?.pngData()
            #else
            let data = renderer.nsImage.flatMap(\.tiffRepresentation)
                .flatMap(NSBitmapImageRep.init(data:))
                .flatMap { $0.representation(using: .png, properties: [:]) }
            #endif
            let png = try #require(data)
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try png.write(to: dir.appendingPathComponent(
                "snapshot-embeds-\(language == .de ? "de" : "en").png"))
        }
    }
}

@Suite("Thread fixture")
struct ThreadFixtureTests {

    /// The offsets are the point of this: a facet that is off by one byte
    /// highlights the wrong text, and an accent before a handle is exactly how
    /// that happens.
    @Test("A mention is indexed in UTF-8 bytes, on the byte the handle starts at")
    func mentionOffsets() throws {
        let replies = ThreadFixture.replies
        let mentioning = replies.filter { $0.record.facets?.isEmpty == false }
        #expect(mentioning.count == 2)

        for post in mentioning {
            let bytes = Array(post.record.text.utf8)
            for facet in try #require(post.record.facets) {
                let slice = bytes[facet.index.byteStart..<facet.index.byteEnd]
                let text = try #require(String(bytes: slice, encoding: .utf8))
                #expect(text.hasPrefix("@"))
                // The handle in the text is the handle of the account the facet
                // points at — otherwise the link goes somewhere else than it reads.
                let did = facet.features.compactMap { feature -> String? in
                    if case .mention(let did) = feature { return did }
                    return nil
                }.first
                let target = ThreadFixture.everyone.first { $0.did == did }
                #expect("@" + (try #require(target).handle) == text)
            }
        }
    }

    @Test("Everybody in the conversation is somebody, and nobody twice")
    func people() {
        let everyone = ThreadFixture.everyone
        #expect(everyone.count == 6)
        #expect(Set(everyone.map(\.did)).count == 6)
        #expect(Set(everyone.map(\.handle)).count == 6)
        #expect(everyone.allSatisfy { $0.displayName?.isEmpty == false })

        // The thread is a conversation, not a monologue: several accounts
        // speak, and somebody comes back after being answered. Counting inside
        // the replies alone misses that — Anna opens the thread and returns at
        // the end of it, Maria is answered and then answers back.
        let voices = ThreadFixture.everything.map(\.author.handle)
        #expect(Set(voices).count == 6)
        #expect(voices.count > Set(voices).count)

        let returning = Dictionary(grouping: voices, by: { $0 }).filter { $0.value.count > 1 }
        #expect(returning.keys.sorted() == ["anna.pds.example.com", "maria.dev"])
    }
}
