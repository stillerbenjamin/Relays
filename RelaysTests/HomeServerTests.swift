//
//  HomeServerTests.swift
//  RelaysTests
//
//  The sign-in screen answers a question no other client answers, and answers it
//  before anybody has typed a password: where does this account actually live.
//  Everything it needs is public.
//

import Testing
import Foundation
@testable import Relays

@Suite("Home server on the sign-in screen")
struct HomeServerTests {

    /// Resolving on every keystroke would be a request per letter, and a
    /// half-typed handle resolves to nothing anyway.
    @Test("Only something that could be an identifier is looked up",
          arguments: [("", false), ("a", false), ("ann", false), ("anna", false),
                      ("anna.", false), (".com", false), ("a.b", false),
                      ("anna.pds.example.com", true), ("bsky.app", true),
                      ("did:", false), ("did:plc:ragtjsm2j2vknwkz3zp4oxrd", true)])
    func resolvable(_ input: String, _ expected: Bool) {
        #expect(HomeServerLookup.looksResolvable(input) == expected)
    }

    @MainActor
    @Test("Nothing typed, nothing shown")
    func idleByDefault() {
        let lookup = HomeServerLookup()
        #expect(lookup.state == .idle)
        lookup.lookUp("ann")
        #expect(lookup.state == .idle)
    }
}

/// Handle → DID → server → the relay's word about it. Four public lookups and no
/// account anywhere.
@Suite("The sign-in lookup against the live network",
       .disabled("Needs the network; run by hand after touching the sign-in screen"))
struct HomeServerLiveTests {

    @Test("A handle on a Bluesky server resolves to the machine it is on")
    func blueskyHosted() async throws {
        let service = try #require(await PDSDirectory.resolveService(for: "pfrazee.com"))
        let host = service.replacingOccurrences(of: "https://", with: "")
        #expect(host.hasSuffix("host.bsky.network"))

        let status = try await ATProtoClient.hostStatus(hostname: host)
        #expect(status.isBluesky)
        #expect(status.accounts > 0)
        #expect(status.status == "active")
    }

    /// The case the whole line exists for: an account that is not on Bluesky's
    /// machines at all.
    @Test("An independent server is named as itself")
    func selfHosted() async throws {
        let service = try #require(await PDSDirectory.resolveService(for: "blacksky.app"))
        let host = service.replacingOccurrences(of: "https://", with: "")

        let status = try await ATProtoClient.hostStatus(hostname: host)
        #expect(!status.isBluesky)
        #expect(status.accounts > 0)
    }

    @Test("A name the network does not know resolves to nothing, not to a guess")
    func unknown() async {
        let made = "definitely-not-a-handle-\(UUID().uuidString.prefix(8)).example.com"
        #expect(await PDSDirectory.resolveService(for: made) == nil)
    }
}
