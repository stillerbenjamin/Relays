//
//  ProfileCache.swift
//  Relays
//
//  The firehose gives out DIDs. This resolves them to profiles in batches so a fast
//  stream costs a handful of requests rather than one per post.
//

import Foundation
import Observation

@MainActor
@Observable
final class ProfileCache {

    private(set) var profiles: [String: ActorProfile] = [:]
    private var pending: Set<String> = []
    private var requested: Set<String> = []
    private var flushTask: Task<Void, Never>?

    /// Pure lookup — safe to call while a view is being built.
    func profile(for did: String) -> ActorProfile? {
        profiles[did]
    }

    /// Profiles that arrived through another call — the mute and block lists, for
    /// instance — so the moderation screen does not fetch them a second time.
    func store(_ loaded: [ActorProfile]) {
        for profile in loaded {
            profiles[profile.did] = profile
            requested.insert(profile.did)
        }
    }

    /// Queues a DID for the next batch. Call this from a task, not from a body.
    func request(_ did: String, app: AppModel) {
        guard profiles[did] == nil, !requested.contains(did) else { return }
        pending.insert(did)
        scheduleFlush(app: app)
    }

    private func scheduleFlush(app: AppModel) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.flush(app: app)
        }
    }

    private func flush(app: AppModel) async {
        flushTask = nil
        let batch = Array(pending.prefix(25))
        guard !batch.isEmpty else { return }
        pending.subtract(batch)
        requested.formUnion(batch)

        if let loaded = try? await app.client.profiles(actors: batch) {
            for profile in loaded { profiles[profile.did] = profile }
        }
        if !pending.isEmpty { scheduleFlush(app: app) }
    }
}
