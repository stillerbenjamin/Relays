//
//  Labelers.swift
//  Relays
//
//  Moderation services one can choose. A labeler publishes the values it applies
//  and what each of them means; subscribing to one is a line in the account's
//  preferences, so the choice travels with the account.
//
//  Labels reach the app two ways. The appview includes them when asked with the
//  `atproto-accept-labelers` header — and every labeler also answers for its own
//  labels directly, unauthenticated. The second way is here because the first
//  could not be verified: see `LabelerDirectory.fill(labelsFor:)`.
//

import Foundation
import Observation

/// One moderation service as the appview describes it.
struct LabelerService: Decodable, Identifiable, Hashable {
    let uri: String
    let creator: ActorProfile
    var likeCount: Int?
    var policies: Policies

    var id: String { creator.did }
    var did: String { creator.did }
    var name: String { creator.name }

    struct Policies: Decodable, Hashable {
        var labelValues: [String] = []
        var labelValueDefinitions: [Definition]?
    }

    /// What a value means, in the labeler's own words.
    struct Definition: Decodable, Hashable {
        let identifier: String
        var severity: String?
        var blurs: String?
        var defaultSetting: String?
        var adultOnly: Bool?
        var locales: [Locale]?

        struct Locale: Decodable, Hashable {
            let lang: String
            let name: String
            var description: String?
        }

        /// The name in the reader's language if the labeler wrote one, English if
        /// it did not, and the bare value as a last resort.
        var localisedName: String {
            preferred?.name ?? identifier
        }

        var localisedDescription: String? { preferred?.description }

        private var preferred: Locale? {
            let wanted = L10n.language.resolved == .de ? "de" : "en"
            return locales?.first { $0.lang.hasPrefix(wanted) }
                ?? locales?.first { $0.lang.hasPrefix("en") }
                ?? locales?.first
        }

        /// Into the shape the decision works with.
        var asDefinition: LabelDefinition {
            LabelDefinition(
                identifier: identifier,
                blurs: {
                    switch blurs {
                    case "content": return .content
                    case "media": return .media
                    default: return .none
                    }
                }(),
                severity: {
                    switch severity {
                    case "alert": return .alert
                    case "none": return .none
                    default: return .inform
                    }
                }(),
                defaultSetting: LabelVisibility(stored: defaultSetting ?? "warn"),
                adultOnly: adultOnly ?? false,
                name: localisedName)
        }
    }

    var definitions: [Definition] { policies.labelValueDefinitions ?? [] }
}

@MainActor
@Observable
final class LabelerDirectory {

    /// Services the account subscribes to, in the order the preferences list them.
    private(set) var subscribed: [String] = []
    private(set) var services: [String: LabelerService] = [:]
    /// Labels fetched from a labeler directly, keyed by the subject they are on.
    private(set) var extraLabels: [String: [ContentLabel]] = [:]
    private(set) var isLoading = false

    /// Endpoints resolved out of DID documents, so a labeler is asked only once
    /// where it lives.
    private var endpoints: [String: URL] = [:]
    private var askedFor: Set<String> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 2 << 20, diskCapacity: 16 << 20)
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Reading

    func service(_ did: String) -> LabelerService? { services[did] }

    func isSubscribed(_ did: String) -> Bool { subscribed.contains(did) }

    /// The definition a labeler published for one of its values, if it published
    /// one. Values defined by the protocol itself win — nobody redefines `!hide`.
    func definition(for value: String, from labeler: String?) -> LabelDefinition? {
        if let global = LabelCatalog.definition(for: value) { return global }
        guard let labeler,
              let match = services[labeler]?.definitions.first(where: { $0.identifier == value })
        else { return nil }
        return match.asDefinition
    }

    /// Every value the subscribed services can apply, for the settings screen.
    var adjustableValues: [(labeler: LabelerService, definitions: [LabelerService.Definition])] {
        subscribed.compactMap { did in
            guard let service = services[did] else { return nil }
            let definitions = service.definitions
                .filter { LabelCatalog.definition(for: $0.identifier) == nil }
                .sorted { $0.localisedName < $1.localisedName }
            guard !definitions.isEmpty else { return nil }
            return (labeler: service, definitions: definitions)
        }
    }

    // MARK: - Loading

    func setSubscribed(_ dids: [String], client: ATProtoClient) async {
        subscribed = dids
        await client.setAcceptedLabelers(dids)
        await loadServices(client: client)
    }

    func loadServices(client: ATProtoClient) async {
        let missing = subscribed.filter { services[$0] == nil }
        guard !missing.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        if let loaded = try? await client.labelerServices(dids: missing) {
            for service in loaded { services[service.did] = service }
        }
    }

    /// Looks up one service that is not subscribed to yet, so it can be shown
    /// before the choice is made.
    func preview(_ did: String, client: ATProtoClient) async -> LabelerService? {
        if let known = services[did] { return known }
        guard let loaded = try? await client.labelerServices(dids: [did]).first else { return nil }
        services[did] = loaded
        return loaded
    }

    func forget() {
        subscribed = []
        services = [:]
        extraLabels = [:]
        endpoints = [:]
        askedFor = []
    }

    // MARK: - The second way to a label

    /// Asks every subscribed labeler about these posts itself.
    ///
    /// The header path could not be confirmed: a post that a labeler demonstrably
    /// labels came back from the public appview with no labels on it, whichever
    /// services were named in the header. That may only be true of unauthenticated
    /// requests — but a moderation setting that quietly does nothing is the worst
    /// kind of bug, so the app also asks the source. Labels found here are merged
    /// with whatever the appview sent.
    func fill(labelsFor uris: [String]) async {
        let wanted = uris.filter { !askedFor.contains($0) }
        guard !wanted.isEmpty, !subscribed.isEmpty else { return }
        askedFor.formUnion(wanted)

        for did in subscribed {
            guard let endpoint = await endpoint(for: did) else { continue }
            guard let labels = try? await ATProtoClient.queryLabels(
                at: endpoint, uris: Array(wanted.prefix(25)), session: session) else { continue }

            for label in labels where !label.isNegated {
                guard let subject = label.uri else { continue }
                var existing = extraLabels[subject] ?? []
                if !existing.contains(where: { $0.src == label.src && $0.val == label.val }) {
                    existing.append(label)
                    extraLabels[subject] = existing
                }
            }
        }
    }

    func labels(for uri: String) -> [ContentLabel] { extraLabels[uri] ?? [] }

    /// A labeler names its own address in its DID document, under
    /// `#atproto_labeler` — the same place a PDS is named.
    private func endpoint(for did: String) async -> URL? {
        if let known = endpoints[did] { return known }
        guard let document = await PDSDirectory.document(for: did),
              let endpoint = PDSDirectory.serviceEndpoint(in: document, type: "AtprotoLabeler")
        else { return nil }
        endpoints[did] = endpoint
        return endpoint
    }
}
