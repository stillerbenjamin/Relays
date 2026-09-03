//
//  HostRegisterTests.swift
//  RelaysTests
//
//  The readings screen has been estimating the shape of the network from a
//  firehose sample. The relay publishes the register, unauthenticated, and it
//  says something the sample cannot: how many servers exist rather than how many
//  are writing this minute.
//

import Testing
import Foundation
@testable import Relays

@Suite("Host register")
struct HostRegisterTests {

    private func host(_ name: String, accounts: Int, status: String) -> RelayHost {
        RelayHost(hostname: name, seq: nil, accountCount: accounts, status: status)
    }

    /// The shape the relay actually sends, taken from a live reply.
    @Test("A page decodes as the relay writes it")
    func decodesLiveShape() throws {
        let json = Data(#"""
        {"cursor":"5","hosts":[
          {"accountCount":126728,"hostname":"lepista.us-west.host.bsky.network",
           "seq":307660059,"status":"active"},
          {"accountCount":40772,"hostname":"blacksky.app","seq":56904125,"status":"active"}]}
        """#.utf8)

        let page = try JSONDecoder().decode(HostPage.self, from: json)
        #expect(page.cursor == "5")
        #expect(page.hosts.count == 2)
        #expect(page.hosts[1].hostname == "blacksky.app")
        #expect(page.hosts[1].accounts == 40_772)
    }

    /// `hostStatus` is a known-values list in the lexicon, not a closed set. A
    /// status nobody has seen yet must not take the page down with it.
    @Test("A status this app has never heard of survives")
    func unknownStatus() throws {
        let json = Data(#"{"hosts":[{"hostname":"a.example.com","status":"quarantined"}]}"#.utf8)
        let page = try JSONDecoder().decode(HostPage.self, from: json)
        #expect(page.hosts.first?.status == "quarantined")
        // Shown as the server wrote it rather than dropped or renamed.
        #expect(HostsView.label(for: "quarantined") == "quarantined")
    }

    @Test("A host with no account count is not a host with none")
    func missingCount() throws {
        let json = Data(#"{"hosts":[{"hostname":"a.example.com"}]}"#.utf8)
        let page = try JSONDecoder().decode(HostPage.self, from: json)
        let host = try #require(page.hosts.first)
        #expect(host.accountCount == nil)
        #expect(host.accounts == 0)
    }

    /// The distinction the whole screen exists for.
    @Test("Bluesky's own servers are told apart from everybody else's")
    func independence() {
        #expect(host("porcini.us-east.host.bsky.network", accounts: 1, status: "active").isBluesky)
        #expect(host("bsky.social", accounts: 1, status: "active").isBluesky)
        #expect(!host("blacksky.app", accounts: 1, status: "active").isBluesky)
        #expect(!host("eurosky.social", accounts: 1, status: "active").isBluesky)
        // A lookalike is not the same domain.
        #expect(!host("notbsky.network.example.com", accounts: 1, status: "active").isBluesky)
    }

    @Test("The totals are the headline, so they are counted here and not in a view")
    func totals() {
        let totals = HostTotals.of([
            host("a.us-west.host.bsky.network", accounts: 100_000, status: "active"),
            host("b.us-west.host.bsky.network", accounts: 50_000, status: "active"),
            host("blacksky.app", accounts: 40_000, status: "active"),
            host("small.example.com", accounts: 12, status: "offline"),
            host("gone.example.com", accounts: 0, status: "offline"),
            host("bad.example.com", accounts: 3, status: "banned")
        ])

        #expect(totals.hosts == 6)
        #expect(totals.independent == 4)
        #expect(totals.accounts == 190_015)
        #expect(totals.accountsOnIndependent == 40_015)
        // Biggest group first.
        #expect(totals.byStatus.map(\.status) == ["active", "offline", "banned"])
        #expect(totals.byStatus.map(\.count) == [3, 2, 1])
    }

    @Test("An empty register adds up to nothing rather than crashing")
    func emptyTotals() {
        #expect(HostTotals.of([]) == HostTotals())
    }

    // MARK: - Filtering

    @MainActor
    @Test("Search matches the hostname, and the filter matches the status")
    func filtering() {
        let model = HostsModel()
        model.applyForTesting([
            host("blacksky.app", accounts: 40_000, status: "active"),
            host("eurosky.social", accounts: 30_000, status: "active"),
            host("gone.example.com", accounts: 0, status: "offline")
        ])

        #expect(model.matches(query: "", status: nil).count == 3)
        #expect(model.matches(query: "sky", status: nil).map(\.hostname)
                == ["blacksky.app", "eurosky.social"])
        #expect(model.matches(query: "", status: "offline").map(\.hostname) == ["gone.example.com"])
        #expect(model.matches(query: "sky", status: "offline").isEmpty)
        // Biggest first, without being asked.
        #expect(model.matches(query: "", status: nil).first?.hostname == "blacksky.app")
    }
}

/// The register is public. This needs a network and no account.
@Suite("The register against the live network",
       .disabled("Needs the network; run by hand after touching the register"))
struct HostRegisterLiveTests {

    @Test("A relay hands out its register, and it is mostly not Bluesky")
    func register() async throws {
        let page = try await ATProtoClient.relayHosts(limit: 1_000)
        #expect(page.hosts.count > 500)
        #expect(page.cursor != nil)

        let totals = HostTotals.of(page.hosts)
        #expect(totals.accounts > 0)
        // Every host carries a status the app can colour.
        #expect(page.hosts.allSatisfy { ($0.status ?? "").isEmpty == false })
    }

    @Test("One server can be asked about by name")
    func single() async throws {
        let host = try await ATProtoClient.hostStatus(hostname: "blacksky.app")
        #expect(host.hostname == "blacksky.app")
        #expect(!host.isBluesky)
        #expect(host.accounts > 0)
    }
}
