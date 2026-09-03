//
//  RelayView.swift
//  Relays
//
//  The network itself, in two sizes. A hairline under the wordmark that moves
//  with the firehose, and the full readings behind a tap on the title.
//

import SwiftUI

// MARK: - The line

/// A minute of throughput drawn across the width. Oldest at the left, the
/// second still being written at the right.
struct RelayPulse: View {

    enum Style {
        /// Replaces the hairline under a header: brightness, not amplitude.
        case line
        /// A readable chart with height.
        case bars
    }

    let buckets: [Int]
    var style: Style = .line
    var height: CGFloat = 1

    var body: some View {
        let peak = max(buckets.max() ?? 0, 1)
        let floor = buckets.min() ?? 0
        // A busy minute varies by a few per cent around a high number. Measured
        // against zero that reads as one flat bar, so the contrast comes from the
        // range and only the presence from the absolute rate.
        let span = Double(max(peak - floor, 1))

        Canvas(opaque: false) { context, size in
            guard !buckets.isEmpty else { return }
            let slot = size.width / CGFloat(buckets.count)

            if style == .line {
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Theme.Palette.hairline))
            }

            for (index, value) in buckets.enumerated() {
                guard value > 0 else { continue }
                let level = min(1, Double(value) / Double(peak))
                let contrast = min(1, Double(value - floor) / span)
                let x = CGFloat(index) * slot

                switch style {
                case .line:
                    // Drawn over the hairline, so a quiet stretch stays a hairline
                    // and a busy one glows. The half point of overlap prevents seams.
                    let slice = CGRect(x: x, y: 0, width: slot + 0.5, height: size.height)
                    context.fill(Path(slice),
                                 with: .color(Theme.Palette.accent
                                    .opacity(0.12 + 0.2 * level + 0.5 * contrast)))

                case .bars:
                    let bar = max(1.5, size.height * CGFloat(level))
                    let slice = CGRect(x: x, y: size.height - bar,
                                       width: max(1, slot - 1), height: bar)
                    context.fill(Path(roundedRect: slice, cornerRadius: 1),
                                 with: .color(Theme.Palette.accent
                                    .opacity(0.4 + 0.6 * contrast)))
                }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

/// The line as it sits under the timeline header: subscribes while it is on
/// screen and the app is in front, and lets go otherwise. Kept separate so the
/// four-times-a-second redraw invalidates this view and nothing above it.
struct RelayPulseLine: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var phase

    @State private var holding = false

    var body: some View {
        RelayPulse(buckets: app.relay.buckets)
            .onAppear { hold() }
            .onDisappear { release() }
            .onChange(of: phase) { _, current in
                current == .active ? hold() : release()
            }
    }

    private func hold() {
        guard !holding else { return }
        holding = true
        app.relay.attach()
    }

    private func release() {
        guard holding else { return }
        holding = false
        app.relay.detach()
    }
}

// MARK: - The readings

struct RelayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var phase

    @State private var holding = false
    @State private var previousStream: RadarStream = .posts
    @State private var showsHosts = false

    private var relay: RelayMonitor { app.relay }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.relayTitle)) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    status
                    throughput
                    numbers
                    if relay.stream == .all { composition }
                    servers
                    ticker

                    Text(L(.relayHint))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .sheet(isPresented: $showsHosts) {
            HostsView()
                .presentationBackground(Theme.Palette.background)
                .sheetSize()
        }
        .onAppear {
            previousStream = relay.stream
            hold()
            // The header watches posts alone; here the whole network is the point.
            relay.setStream(.all)
        }
        .onDisappear {
            relay.setStream(previousStream)
            release()
        }
        .onChange(of: phase) { _, current in
            current == .active ? hold() : release()
        }
    }

    // MARK: Sections

    private var status: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColour)
                .frame(width: 7, height: 7)

            Text(statusLabel)
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(relay.host.label)
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Palette.textTertiary)

            Spacer(minLength: 8)
        }
    }

    private var throughput: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L(.relayThroughput))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.rate(relay.perSecond))
                    .font(Theme.Font.mono(34, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(L(.relayPerSecond))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            RelayPulse(buckets: relay.buckets, style: .bars, height: 56)
                .frame(maxWidth: .infinity)

            MonoSegment(selection: Binding(get: { relay.stream },
                                           set: { relay.setStream($0) }),
                        options: RadarStream.allCases,
                        label: \.label)
        }
    }

    private var numbers: some View {
        HStack(alignment: .top, spacing: 12) {
            reading(L(.relayLatency),
                    value: relay.latency.map { String(format: "%.0f ms", $0 * 1000) } ?? "—",
                    note: L(.relayLatencyHint))
            reading(L(.relaySeen), value: Format.grouped(relay.seen), note: nil)
        }
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(L(.relayComposition))

            let total = max(relay.counts.values.reduce(0, +), 1)
            ForEach([RadarEvent.Kind.post, .like, .repost, .follow], id: \.self) { kind in
                let count = relay.counts[kind] ?? 0
                share(label: kind.label, count: count, total: total)
            }
        }
    }

    private var servers: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Named a sample now that a census sits under it. The two count
            // different populations and the screen would lie by conflating them.
            sectionTitle(L(.relaySampleTitle))

            if relay.sampledAccounts == 0 {
                Text(L(.relayWaiting))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                let total = max(relay.sampledAccounts, 1)
                ForEach(relay.serverRanking.prefix(6), id: \.host) { entry in
                    share(label: entry.host, count: entry.count, total: total)
                }

                HStack(spacing: 6) {
                    Text(L(.relaySample, relay.sampledAccounts))
                    Text("·")
                    Text("\(RelayShareBar.percent(relay.selfHosted, of: total)) \(L(.relaySelfHosted))")
                }
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.top, 2)
            }

            Button { showsHosts = true } label: {
                HStack(spacing: 5) {
                    Text(L(.hostsOpen))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(Theme.Font.ui(12, .medium))
                .foregroundStyle(Theme.Palette.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var ticker: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(L(.relayLatest))
                .padding(.bottom, 9)

            ForEach(relay.latest.prefix(24)) { event in
                Button {
                    open(event)
                } label: {
                    RelayEventRow(event: event)
                }
                .buttonStyle(.plain)
                .disabled(event.threadURI == nil)

                Hairline()
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        RelaySectionTitle(text: text)
    }

    private func reading(_ label: String, value: String, note: String?) -> some View {
        RelayReading(label: label, value: value, note: note)
    }

    private func share(label: String, count: Int, total: Int) -> some View {
        RelayShareBar(label: label, count: count, total: total)
    }

    /// Rates below ten are worth a decimal; above it the decimal is noise.
    static func rate(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    private var statusColour: Color {
        switch relay.status {
        case .live: return Theme.Palette.repost
        case .connecting, .idle: return Theme.Palette.textTertiary
        case .failed: return Theme.Palette.danger
        }
    }

    private var statusLabel: String {
        switch relay.status {
        case .live: return L(.relayLive)
        case .connecting: return L(.relayConnecting)
        case .idle: return L(.relayOffline)
        case .failed(let message): return message
        }
    }

    private func open(_ event: RadarEvent) {
        guard let uri = event.threadURI else { return }
        dismiss()
        // The sheet has to be out of the way before the tab pushes behind it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            navigate(.thread(uri: uri))
        }
    }

    private func hold() {
        guard !holding else { return }
        holding = true
        relay.attach()
    }

    private func release() {
        guard holding else { return }
        holding = false
        relay.detach()
    }
}

struct RelaySectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.mono(10, .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}

/// A single number with its name and, where it needs one, what it means.
struct RelayReading: View {
    let label: String
    let value: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RelaySectionTitle(text: label)
            Text(value)
                .font(Theme.Font.mono(19, .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            if let note {
                Text(note)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of a proportion: what it is, what share it holds, and a bar for the eye.
struct RelayShareBar: View {
    let label: String
    let count: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Self.percent(count, of: total))
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.surface)
                    Capsule()
                        .fill(Theme.Palette.accent)
                        .frame(width: proxy.size.width * CGFloat(share))
                }
            }
            .frame(height: 4)
        }
    }

    private var share: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(count) / Double(total))
    }

    static func percent(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "0 %" }
        return String(format: "%.0f %%", 100 * Double(count) / Double(total))
    }
}

/// One record as it came off the wire: no profile, no counts, nothing fetched.
struct RelayEventRow: View {
    let event: RadarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.symbol)
                .font(.system(size: 11))
                .foregroundStyle(colour)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.shortDID)
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)

                if !event.text.isEmpty {
                    Text(event.text)
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let target {
                    // Likes, reposts and follows carry no text of their own. The
                    // symbol already says which of the three this is, so the row
                    // only has to name what it points at.
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                        Text(target)
                    }
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if event.hasMedia {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// The account a like, repost or follow points at, shortened the same way
    /// the actor's own DID is.
    private var target: String? {
        guard let subject = event.subject else { return nil }
        let did = subject.hasPrefix("at://")
            ? String(subject.dropFirst("at://".count).prefix { $0 != "/" })
            : subject
        guard did.hasPrefix("did:plc:") else { return did }
        return String(did.dropFirst("did:plc:".count).prefix(10))
    }

    private var colour: Color {
        switch event.kind {
        case .like: return Theme.Palette.like
        case .repost: return Theme.Palette.repost
        case .post, .follow: return Theme.Palette.textSecondary
        }
    }
}

extension RadarEvent.Kind {
    var label: String {
        switch self {
        case .post: return L(.radarPosts)
        case .like: return L(.radarLikes)
        case .repost: return L(.radarReposts)
        case .follow: return L(.radarFollows)
        }
    }
}
