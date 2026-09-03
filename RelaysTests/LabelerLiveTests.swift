//
//  LabelerLiveTests.swift
//  RelaysTests
//
//  Against the real services. Both paths a label can travel are public, so this
//  needs no account — only the network, which is why it does not run with the
//  rest. Run it by hand after touching the labeler code:
//
//    xcodebuild test -only-testing:RelaysTests/LabelerLiveTests …
//

import Testing
import Foundation
@testable import Relays

@Suite("Labelers against the live network",
       .disabled("Needs the network; run by hand after touching the labeler code"))
struct LabelerLiveTests {

    /// Bluesky's own moderation service, which every account on it gets anyway.
    private let moderation = "did:plc:ar7c4by46qjdydhdevvrndac"

    @Test("A real service decodes with all its definitions")
    func realService() async throws {
        var components = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.labeler.getServices")!
        components.queryItems = [URLQueryItem(name: "dids", value: moderation),
                                 URLQueryItem(name: "detailed", value: "true")]

        struct Response: Decodable { let views: [LabelerService] }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let service = try #require(JSONDecoder().decode(Response.self, from: data).views.first)

        #expect(service.did == moderation)
        #expect(service.creator.isLabeler)
        #expect(service.policies.labelValues.count > 10)

        // A service publishes definitions only for its own values. The ones the
        // protocol defines — the adult labels and the two system ones — come with
        // no definition at all, which is why the app has to carry them itself.
        let defined = Set(service.definitions.map(\.identifier))
        let applied = Set(service.policies.labelValues)
        let undefined = applied.subtracting(defined)

        #expect(undefined.allSatisfy { LabelCatalog.definition(for: $0) != nil },
                "no definition anywhere for: \(undefined.sorted().joined(separator: ", "))")
        // The four the app hardcodes are exactly the ones this service leans on.
        #expect(undefined.isSuperset(of: ["porn", "nudity", "sexual", "graphic-media"]))

        // The fields the decision runs on have to be there and map cleanly.
        for published in service.definitions {
            let definition = published.asDefinition
            #expect(!definition.title.isEmpty)
            #expect(published.locales?.isEmpty == false)
        }

        print("live labeler: \(service.name), \(service.policies.labelValues.count) values, "
              + "\(service.definitions.count) definitions")
    }

    /// The path that does not depend on the appview honouring a header: ask the
    /// labeler itself. This is the one measured to work.
    @Test("A labeler answers for its own labels")
    func directQuery() async throws {
        // A small service with a single value, so the answer is unambiguous.
        let substack = "did:plc:uxjwly6emtgik7juvxxdpl3c"

        let document = try #require(await PDSDirectory.document(for: substack))
        let endpoint = try #require(PDSDirectory.serviceEndpoint(in: document, type: "AtprotoLabeler"))
        print("live labeler endpoint: \(endpoint.absoluteString)")

        let labels = try await ATProtoClient.queryLabels(at: endpoint, uris: ["*"])
        let label = try #require(labels.first)

        #expect(label.src == substack)
        #expect(label.val == "substack")
        #expect(label.uri?.hasPrefix("at://") == true)
        #expect(!label.isNegated)

        print("live labeler: \(labels.count) labels, first on \(label.uri ?? "—")")
    }
}

@Suite("Lists against the live network",
       .disabled("Needs the network; run by hand after touching the list code"))
struct ListLiveTests {

    /// A real moderation list, big enough that its shape is not an accident.
    private let scrapers = "at://did:plc:7clbywj3lmesv6utxqocmzdy/app.bsky.graph.list/3lbqvvdsz7p2y"

    @Test("A moderation list decodes with its members")
    func realList() async throws {
        var components = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.graph.getList")!
        components.queryItems = [URLQueryItem(name: "list", value: scrapers),
                                 URLQueryItem(name: "limit", value: "10")]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)

        #expect(response.list.uri == scrapers)
        #expect(response.list.isModeration, "purpose was \(response.list.purpose ?? "—")")
        #expect((response.list.listItemCount ?? 0) > 100)
        // A page comes back shorter than the limit when members have since been
        // deleted or taken down: eight of ten, on the day this was written. A
        // short page is not the end of the list, and the count on the list is not
        // what one can actually see.
        #expect(!response.items.isEmpty)
        #expect(response.items.count <= 10)
        #expect(response.items.allSatisfy { $0.subject.did.hasPrefix("did:") })
        #expect(response.cursor != nil)

        print("live list: \(response.list.name), \(response.list.listItemCount ?? 0) accounts, "
              + "first \(response.items[0].subject.handle)")
    }

    @Test("A curation list is not mistaken for a moderation one")
    func curationList() async throws {
        var components = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.graph.getLists")!
        components.queryItems = [
            URLQueryItem(name: "actor", value: "did:plc:z72i7hdynmk6r22z27h6tvur"),
            URLQueryItem(name: "limit", value: "5")]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ListsResponse.self, from: data)
        let list = try #require(response.lists.first)

        // Only a modlist gets the mute and block controls; this one is read.
        #expect(!list.isModeration, "purpose was \(list.purpose ?? "—")")
        print("live list: \(list.name) is \(list.purpose ?? "—")")
    }
}

/// Sign-up itself is parked (`Parked/SignUp/`), but what a server says about
/// itself is public and still worth knowing — it is how the app would ever build
/// a form again, and it is the shape `describeServer` has to keep.
@Suite("Servers describing themselves, live",
       .disabled("Needs the network; run by hand after touching describeServer"))
struct ServerDescriptionLiveTests {

    /// Reads only. Nothing here creates an account.
    @Test("Real servers say what they require, and they do not all say the same")
    func describesServers() async throws {
        let bluesky = try await ATProtoClient.describeServer(host: "bsky.social")
        #expect(bluesky.handleSuffix == ".bsky.social")
        #expect(bluesky.termsURL != nil)
        #expect(bluesky.privacyPolicyURL != nil)
        // The one that shapes the form: Bluesky's host verifies by text message.
        #expect(bluesky.needsPhone)
        #expect(!bluesky.needsInviteCode)

        // A host in the same network that wants an invitation instead — proof
        // that the two requirements really do differ per server.
        let hosted = try await ATProtoClient.describeServer(
            host: "panus.us-west.host.bsky.network")
        #expect(hosted.needsInviteCode)

        print("live signup: bsky.social phone=\(bluesky.needsPhone) "
              + "invite=\(bluesky.needsInviteCode) suffix=\(bluesky.handleSuffix)")
        print("live signup: hosted invite=\(hosted.needsInviteCode)")
    }

}


@Suite("Discovery against the live network",
       .disabled("Needs the network; run by hand after touching the search screen"))
struct DiscoveryLiveTests {

    /// The one discovery surface that answers without a session — which is why
    /// the empty search screen can show something to anybody.
    @Test("Popular feeds come back with what the row needs")
    func popularFeeds() async throws {
        var components = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.unspecced.getPopularFeedGenerators")!
        components.queryItems = [URLQueryItem(name: "limit", value: "10")]

        struct Response: Decodable { let feeds: [FeedGeneratorView] }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let feeds = try JSONDecoder().decode(Response.self, from: data).feeds

        #expect(feeds.count == 10)
        #expect(feeds.allSatisfy { !$0.displayName.isEmpty })
        #expect(feeds.allSatisfy { $0.uri.hasPrefix("at://") })
        // The row shows a description and a count where they exist.
        #expect(feeds.contains { $0.description?.isEmpty == false })
        #expect(feeds.contains { ($0.likeCount ?? 0) > 0 })

        print("live discovery: \(feeds.count) feeds, first \(feeds[0].displayName)")
    }
}
