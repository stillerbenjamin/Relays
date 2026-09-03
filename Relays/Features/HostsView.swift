//
//  HostsView.swift
//  Relays
//
//  The relay's register, whole. Six thousand servers is not a list anybody
//  reads top to bottom, so the totals come first and the register is behind a
//  search — the same reasoning as the country picker.
//
//  This is deliberately not a replacement for the sampled ranking on the
//  readings screen. That one answers "who is writing right now"; this one
//  answers "who exists". Two questions, two answers, both labelled.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class HostsModel {
    private(set) var hosts: [RelayHost] = []
    private(set) var totals = HostTotals()
    private(set) var isLoading = true
    private(set) var isPaging = false
    private(set) var errorMessage: String?
    private(set) var fetchedAt: Date?

    var relay: RelayHostName = .default

    /// Seven pages of a thousand covered the whole register when this was
    /// written. The ceiling is here so a relay that has grown, or one that
    /// hands back a cursor forever, cannot spin.
    private static let pageCeiling = 10

    func load(force: Bool = false) async {
        if !force, let cached = HostCache.read(relay: relay) {
            apply(cached.hosts, at: cached.fetchedAt)
            isLoading = false
            return
        }
        await fetch()
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        errorMessage = nil
        isPaging = !hosts.isEmpty
        var collected: [RelayHost] = []
        var cursor: String?

        do {
            for _ in 0..<Self.pageCeiling {
                let page = try await ATProtoClient.relayHosts(relay: relay, cursor: cursor)
                collected += page.hosts
                cursor = page.cursor
                if page.cursor == nil || page.hosts.isEmpty { break }
                // The first page is enough to show; the rest fills in behind it.
                if collected.count == page.hosts.count { apply(collected, at: nil) }
            }
            apply(collected, at: Date())
            HostCache.write(collected, relay: relay)
        } catch {
            if hosts.isEmpty {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
        isPaging = false
    }

    #if DEBUG
    /// Only used by tests; there is no path to it from the app.
    func applyForTesting(_ hosts: [RelayHost]) {
        apply(hosts, at: Date())
        isLoading = false
    }
    #endif

    private func apply(_ hosts: [RelayHost], at date: Date?) {
        self.hosts = hosts.sorted { $0.accounts > $1.accounts }
        self.totals = HostTotals.of(hosts)
        if let date { fetchedAt = date }
    }

    /// Filtering is a plain substring over the hostname plus the status, both of
    /// which are what a person actually looks for.
    func matches(query: String, status: String?) -> [RelayHost] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return hosts.filter { host in
            if let status, host.status != status { return false }
            guard !text.isEmpty else { return true }
            return host.hostname.lowercased().contains(text)
        }
    }
}

/// One blob per relay in the caches directory. Not SwiftData: `FeedCache` owns
/// that container, and adding a second model to its schema risks a migration
/// that would silently take the feed cache with it.
enum HostCache {
    private static func url(relay: RelayHostName) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("hosts-\(relay.rawValue).json")
    }

    private struct Stored: Codable {
        let hosts: [RelayHost]
        let fetchedAt: Date
    }

    /// An hour. The register changes slowly and six thousand rows is not a
    /// request to repeat on every glance.
    static let maximumAge: TimeInterval = 3_600

    static func read(relay: RelayHostName) -> (hosts: [RelayHost], fetchedAt: Date)? {
        guard let url = url(relay: relay),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              Date().timeIntervalSince(stored.fetchedAt) < maximumAge
        else { return nil }
        return (stored.hosts, stored.fetchedAt)
    }

    static func write(_ hosts: [RelayHost], relay: RelayHostName) {
        guard let url = url(relay: relay),
              let data = try? JSONEncoder().encode(Stored(hosts: hosts, fetchedAt: Date()))
        else { return }
        try? data.write(to: url)
    }
}

struct HostsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: HostsModel

    /// The model is injectable so a snapshot can be taken of a filled register
    /// without a network.
    @MainActor
    init(model: HostsModel? = nil) {
        _model = State(initialValue: model ?? HostsModel())
    }

    @State private var query = ""
    @State private var status: String?

    private var shown: [RelayHost] { model.matches(query: query, status: status) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.hostsTitle), onRefresh: { await model.refresh() }) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            if model.isLoading {
                LoadingList()
            } else if let error = model.errorMessage, model.hosts.isEmpty {
                StateMessage(text: error, systemImage: "antenna.radiowaves.left.and.right.slash") {
                    Task { await model.load(force: true) }
                }
                Spacer()
            } else {
                list
            }
        }
        .relaysBackground()
        .task { await model.load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HostTotalsView(totals: model.totals)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.vertical, 18)

                search
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.bottom, 14)

                Hairline()

                if shown.isEmpty {
                    Text(L(.hostsEmpty))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(Theme.Metric.hPadding)
                } else {
                    ForEach(shown) { host in
                        HostRow(host: host)
                        Hairline(inset: Theme.Metric.hPadding)
                    }
                }

                if model.isPaging {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }

                Text(L(.hostsRelayNote, model.relay.rawValue))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Metric.hPadding)
            }
        }
        .scrollIndicators(.never)
    }

    // MARK: - Finding one

    private var search: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoField(icon: "magnifyingglass", placeholder: L(.hostsSearch), text: $query)

            let options = [nil] + model.totals.byStatus.map { Optional($0.status) }
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        status = option
                    } label: {
                        Text(option.map(Self.label(for:)) ?? L(.hostsAll))
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(status == option ? Theme.Palette.background
                                                              : Theme.Palette.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(status == option ? Theme.Palette.textPrimary
                                                                : Theme.Palette.surface))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - The server's own vocabulary

    /// The lexicon calls these known values rather than a closed set, so an
    /// unfamiliar one is shown as the server wrote it instead of being dropped.
    static func label(for status: String) -> String {
        switch status {
        case "active": return L(.hostsStatusActive)
        case "idle": return L(.hostsStatusIdle)
        case "offline": return L(.hostsStatusOffline)
        case "throttled": return L(.hostsStatusThrottled)
        case "banned": return L(.hostsStatusBanned)
        default: return status
        }
    }

    static func colour(for status: String) -> Color {
        switch status {
        case "active": return Theme.Palette.repost
        case "idle", "throttled": return Theme.Palette.textTertiary
        case "banned": return Theme.Palette.danger
        default: return Theme.Palette.hairline
        }
    }
}


/// What the register adds up to. Its own type so it can be looked at without a
/// scroll view around it — a `LazyVStack` draws nothing inside a renderer.
struct HostTotalsView: View {
    let totals: HostTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(.hostsHint))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                figure(Format.grouped(totals.hosts), L(.relayServers))
                figure(Format.grouped(totals.independent), L(.hostsIndependent))
                figure(Format.compact(totals.accounts), L(.hostsAccounts))
            }

            Text(L(.hostsOfWhich, Format.grouped(totals.accountsOnIndependent)))
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)

            if !totals.byStatus.isEmpty {
                HStack(spacing: 12) {
                    ForEach(totals.byStatus.prefix(4), id: \.status) { entry in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(HostsView.colour(for: entry.status))
                                .frame(width: 6, height: 6)
                            Text("\(Format.grouped(entry.count)) \(HostsView.label(for: entry.status))")
                                .font(Theme.Font.mono(10))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Font.mono(19))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}

/// One server. Bluesky's own are dimmed, because the interesting ones are the
/// others.
struct HostRow: View {
    let host: RelayHost

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(HostsView.colour(for: host.status ?? ""))
                .frame(width: 7, height: 7)

            Text(host.hostname)
                .font(Theme.Font.mono(12))
                .foregroundStyle(host.isBluesky ? Theme.Palette.textSecondary
                                                : Theme.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(Format.grouped(host.accounts))
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.hostname), \(HostsView.label(for: host.status ?? "")), "
                            + "\(host.accounts) \(L(.hostsAccounts))")
    }
}
