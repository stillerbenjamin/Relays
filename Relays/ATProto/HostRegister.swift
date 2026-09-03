//
//  HostRegister.swift
//  Relays
//
//  The relay keeps a register of every server it consumes from, and hands it
//  out to anybody who asks. The app has been estimating that number from a
//  firehose sample — which answers a different question. A sample says who is
//  writing right now, weighted by how much they write. The register says who
//  exists, weighted by how many accounts they hold. Both are worth knowing and
//  neither replaces the other.
//
//  Measured against relay1.us-west.bsky.network: 6156 hosts, of which 89 are
//  Bluesky's own.
//

import Foundation

/// One server as the relay knows it.
struct RelayHost: Codable, Identifiable, Hashable {
    let hostname: String
    var seq: Int?
    var accountCount: Int?
    /// `active`, `idle`, `offline`, `throttled`, `banned` — and whatever comes
    /// next. The lexicon calls these known values, not a closed set, so a new
    /// one must not take the page down with it.
    var status: String?

    var id: String { hostname }

    /// Bluesky runs its own servers under one domain. Everything else is
    /// somebody who chose to host themselves, which is the number this app is
    /// actually about.
    var isBluesky: Bool {
        hostname.hasSuffix(".bsky.network") || hostname == "bsky.social"
    }

    var accounts: Int { accountCount ?? 0 }
}

struct HostPage: Decodable {
    let hosts: [RelayHost]
    var cursor: String?
}

/// What the register adds up to. Kept apart from the view so the arithmetic can
/// be tested without one.
struct HostTotals: Equatable {
    var hosts: Int = 0
    var independent: Int = 0
    var accounts: Int = 0
    var accountsOnIndependent: Int = 0
    /// Counted by the server's own word, in the order they are shown.
    var byStatus: [(status: String, count: Int)] = []

    static func == (a: HostTotals, b: HostTotals) -> Bool {
        a.hosts == b.hosts && a.independent == b.independent
            && a.accounts == b.accounts && a.accountsOnIndependent == b.accountsOnIndependent
            && a.byStatus.map(\.status) == b.byStatus.map(\.status)
            && a.byStatus.map(\.count) == b.byStatus.map(\.count)
    }

    static func of(_ hosts: [RelayHost]) -> HostTotals {
        var totals = HostTotals()
        var counts: [String: Int] = [:]
        for host in hosts {
            totals.hosts += 1
            totals.accounts += host.accounts
            if !host.isBluesky {
                totals.independent += 1
                totals.accountsOnIndependent += host.accounts
            }
            counts[host.status ?? "", default: 0] += 1
        }
        // Biggest group first, and ties broken by name so the order is stable.
        totals.byStatus = counts
            .filter { !$0.key.isEmpty }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (status: $0.key, count: $0.value) }
        return totals
    }
}

/// The relays the app knows how to ask. A relay is not the account's own server,
/// so this is a list of its own — the same shape as `JetstreamHost`.
enum RelayHostName: String, CaseIterable, Identifiable, Codable {
    case usWest = "relay1.us-west.bsky.network"
    case usEast = "relay1.us-east.bsky.network"

    var id: String { rawValue }
    var url: String { "https://\(rawValue)" }
    static let `default` = RelayHostName.usWest
}
