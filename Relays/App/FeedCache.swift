//
//  FeedCache.swift
//  Relays
//
//  The last page of each feed, kept on disk with SwiftData so the app opens with
//  content instead of a spinner.
//

import Foundation
import SwiftData

@Model
final class FeedSnapshot {
    /// Feed identity: "timeline", a feed generator URI, or a list URI.
    @Attribute(.unique) var id: String
    /// The account the snapshot belongs to — snapshots must not leak across accounts.
    var did: String
    var payload: Data
    var savedAt: Date

    init(id: String, did: String, payload: Data, savedAt: Date = Date()) {
        self.id = id
        self.did = did
        self.payload = payload
        self.savedAt = savedAt
    }
}

@MainActor
enum FeedCache {

    /// A failure here must never block the app, so the container is optional.
    static let container: ModelContainer? = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try? ModelContainer(for: FeedSnapshot.self, configurations: configuration)
    }()

    private static let entryLimit = 30

    static func store(_ posts: [FeedViewPost], id: String, did: String) {
        guard let context = container?.mainContext,
              let payload = try? JSONEncoder().encode(Array(posts.prefix(entryLimit))) else { return }

        let descriptor = FetchDescriptor<FeedSnapshot>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.did = did
            existing.savedAt = Date()
        } else {
            context.insert(FeedSnapshot(id: id, did: did, payload: payload))
        }
        try? context.save()
    }

    static func load(id: String, did: String) -> [FeedViewPost] {
        guard let context = container?.mainContext else { return [] }
        let descriptor = FetchDescriptor<FeedSnapshot>(predicate: #Predicate { $0.id == id })
        guard let snapshot = try? context.fetch(descriptor).first, snapshot.did == did else { return [] }
        return (try? JSONDecoder().decode([FeedViewPost].self, from: snapshot.payload)) ?? []
    }

    static func clear() {
        guard let context = container?.mainContext else { return }
        try? context.delete(model: FeedSnapshot.self)
        try? context.save()
    }
}
