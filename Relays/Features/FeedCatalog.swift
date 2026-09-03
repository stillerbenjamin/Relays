//
//  FeedCatalog.swift
//  Relays
//
//  The feeds the account has saved: the following timeline, custom feeds produced by
//  generators, and curated lists — resolved to display names.
//

import Foundation
import Observation

struct FeedEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let source: FeedModel.Source

    static var following: FeedEntry {
        FeedEntry(id: "timeline", title: L(.feedFollowing), source: .timeline)
    }
}

@MainActor
@Observable
final class FeedCatalog {

    private(set) var entries: [FeedEntry] = [.following]
    private(set) var isLoading = false
    private var loaded = false

    func load(app: AppModel) async {
        guard !loaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let saved = try? await app.client.savedFeeds() else { return }
        loaded = true

        let generatorURIs = saved.filter { $0.type == "feed" }.map(\.value)
        let generators = (try? await app.client.feedGenerators(uris: generatorURIs)) ?? []
        let names = Dictionary(uniqueKeysWithValues: generators.map { ($0.uri, $0.displayName) })

        var built: [FeedEntry] = [.following]
        for feed in saved {
            switch feed.type {
            case "feed":
                built.append(FeedEntry(id: feed.value,
                                       title: names[feed.value] ?? Self.shortName(feed.value),
                                       source: .custom(feed.value)))
            case "list":
                let name = (try? await app.client.list(uri: feed.value))?.name
                built.append(FeedEntry(id: feed.value,
                                       title: name ?? Self.shortName(feed.value),
                                       source: .list(feed.value)))
            default:
                continue  // the timeline entry is already first
            }
        }
        entries = built
    }

    /// Falls back to the rkey when a generator will not resolve.
    private static func shortName(_ uri: String) -> String {
        uri.split(separator: "/").last.map(String.init) ?? uri
    }
}
