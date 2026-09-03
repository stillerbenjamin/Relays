//
//  PDSDirectory.swift
//  Relays
//
//  Resolves a DID to the server that actually hosts the account. The information is
//  public — it sits in the DID document — but no client surfaces it.
//

import Foundation
import Observation

struct AccountOrigin: Equatable, Hashable {
    /// Host of the personal data server, without scheme.
    let host: String

    /// Bluesky's own infrastructure, as opposed to a self-hosted server.
    var isBlueskyHosted: Bool {
        host == "bsky.social" || host.hasSuffix(".bsky.network") || host.hasSuffix(".bsky.social")
    }

    /// Short form for the post header: the registrable part of the host.
    var short: String {
        if isBlueskyHosted { return "bsky.social" }
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }
}

@MainActor
@Observable
final class PDSDirectory {

    private(set) var origins: [String: AccountOrigin] = [:]
    private var inFlight: Set<String> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 32 << 20)
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Pure lookup — safe to call while a view is being built. Ask for a missing
    /// origin with `resolve(_:)` from a task instead; starting work here would
    /// mutate state during a view update.
    func origin(for did: String) -> AccountOrigin? {
        origins[did]
    }

    func resolve(_ did: String) {
        guard origins[did] == nil, !inFlight.contains(did) else { return }
        guard let url = Self.documentURL(for: did) else { return }
        inFlight.insert(did)

        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(did) } }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await self?.session.data(for: request),
                  let host = Self.pdsHost(in: data) else { return }
            await MainActor.run { self?.origins[did] = AccountOrigin(host: host) }
        }
    }

    /// Handle or DID to the server that hosts it, without being signed in anywhere.
    /// This is what makes asking people for their server unnecessary: the network
    /// already knows, and the answer is public.
    static func resolveService(for identifier: String,
                               session: URLSession = .shared) async -> String? {
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return nil }

        let did: String
        if cleaned.hasPrefix("did:") {
            did = cleaned
        } else if cleaned.contains("."), let resolved = await resolveHandle(cleaned, session: session) {
            did = resolved
        } else {
            return nil          // A bare word is not a handle; the default applies.
        }

        guard let url = documentURL(for: did) else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let host = pdsHost(in: data) else { return nil }
        return "https://\(host)"
    }

    /// The handle endpoint is public, so any well-known instance can answer it.
    private static func resolveHandle(_ handle: String, session: URLSession) async -> String? {
        struct Response: Decodable { let did: String }
        guard let url = URL(string:
            "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=\(handle)") else {
            return nil
        }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return try? JSONDecoder().decode(Response.self, from: data).did
    }

    /// `did:plc:` resolves through the PLC directory, `did:web:` through the domain itself.
    nonisolated private static func documentURL(for did: String) -> URL? {
        if did.hasPrefix("did:plc:") {
            return URL(string: "https://plc.directory/\(did)")
        }
        if did.hasPrefix("did:web:") {
            let domain = String(did.dropFirst("did:web:".count))
                .replacingOccurrences(of: ":", with: "/")
            guard let decoded = domain.removingPercentEncoding else { return nil }
            return URL(string: "https://\(decoded)/.well-known/did.json")
        }
        return nil
    }

    /// The DID document itself. A DID names every service the account runs — its
    /// server, and for a labeler the address that answers for its labels.
    nonisolated static func document(for did: String, session: URLSession = .shared) async -> Data? {
        guard let url = documentURL(for: did) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return data
    }

    /// One service out of a document, by its declared type.
    nonisolated static func serviceEndpoint(in data: Data, type: String) -> URL? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }
        let entry = document.service?.first { $0.type == type }
        return entry?.serviceEndpoint.flatMap(URL.init(string:))
    }

    private struct Document: Decodable {
        struct Service: Decodable {
            let id: String?
            let type: String?
            let serviceEndpoint: String?
        }
        let service: [Service]?
    }

    private static func pdsHost(in data: Data) -> String? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }
        let entry = document.service?.first {
            $0.type == "AtprotoPersonalDataServer" || ($0.id?.hasSuffix("atproto_pds") ?? false)
        }
        guard let endpoint = entry?.serviceEndpoint, let url = URL(string: endpoint) else { return nil }
        return url.host()
    }
}
