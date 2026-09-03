//
//  OAuthClient.swift
//  Relays
//
//  The OAuth path the protocol actually intends: identity resolution, pushed
//  authorization, PKCE and DPoP-bound tokens.
//
//  Deployment note: `OAuthConfig.clientID` must point at a client-metadata.json
//  served over HTTPS, and the redirect scheme must match its host in reverse-DNS
//  form. Until that file is hosted, the app falls back to app passwords.
//

import Foundation

enum OAuthConfig {
    /// Replace with the hosted metadata document before shipping.
    static let clientID = "https://relays.app/client-metadata.json"
    static let redirectURI = "app.relays:/oauth/callback"
    static let callbackScheme = "app.relays"
    static let scope = "atproto transition:generic"

    /// A metadata document is required by the server; this is what it must contain.
    static var metadataDocument: [String: Any] {
        [
            "client_id": clientID,
            "client_name": "Relays",
            "application_type": "native",
            "dpop_bound_access_tokens": true,
            "grant_types": ["authorization_code", "refresh_token"],
            "redirect_uris": [redirectURI],
            "response_types": ["code"],
            "scope": scope,
            "token_endpoint_auth_method": "none"
        ]
    }
}

struct AuthorizationServer {
    let issuer: String
    let parEndpoint: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
}

struct DPoPTokens {
    var accessToken: String
    var refreshToken: String?
    var did: String
    var handle: String?
    var issuer: String
    var pdsHost: String
    var keyRaw: Data
}

actor OAuthClient {

    private let session = URLSession(configuration: .ephemeral)
    private var nonce: String?

    // MARK: - Discovery

    /// handle → DID → PDS → authorization server.
    func discover(identifier: String) async throws -> (pds: String, server: AuthorizationServer, did: String?) {
        let cleaned = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        var did: String?
        var pds: String

        if cleaned.hasPrefix("did:") {
            did = cleaned
            pds = try await pdsHost(forDID: cleaned)
        } else if cleaned.contains(".") {
            let resolved = try await resolveHandle(cleaned)
            did = resolved
            pds = try await pdsHost(forDID: resolved)
        } else {
            pds = ATProtoClient.defaultService
        }

        if !pds.hasPrefix("http") { pds = "https://" + pds }
        let server = try await authorizationServer(for: pds)
        return (pds, server, did)
    }

    private func resolveHandle(_ handle: String) async throws -> String {
        struct Response: Decodable { let did: String }
        guard let url = URL(string: "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=\(handle)") else {
            throw ATProtoError.invalidURL
        }
        let (data, _) = try await session.data(from: url)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ATProtoError.server(status: 400, error: "HandleNotFound", message: nil)
        }
        return response.did
    }

    private func pdsHost(forDID did: String) async throws -> String {
        struct Document: Decodable {
            struct Service: Decodable {
                let id: String?
                let type: String?
                let serviceEndpoint: String?
            }
            let service: [Service]?
        }

        let url: URL?
        if did.hasPrefix("did:plc:") {
            url = URL(string: "https://plc.directory/\(did)")
        } else if did.hasPrefix("did:web:") {
            let domain = String(did.dropFirst("did:web:".count)).replacingOccurrences(of: ":", with: "/")
            url = URL(string: "https://\(domain)/.well-known/did.json")
        } else {
            url = nil
        }
        guard let url else { throw ATProtoError.invalidURL }

        let (data, _) = try await session.data(from: url)
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
              let endpoint = document.service?.first(where: {
                  $0.type == "AtprotoPersonalDataServer" || ($0.id?.hasSuffix("atproto_pds") ?? false)
              })?.serviceEndpoint else {
            throw ATProtoError.server(status: 404, error: "PDSNotFound", message: nil)
        }
        return endpoint
    }

    private func authorizationServer(for pds: String) async throws -> AuthorizationServer {
        struct Protected: Decodable { let authorization_servers: [String]? }
        struct Metadata: Decodable {
            let issuer: String
            let pushed_authorization_request_endpoint: String
            let authorization_endpoint: String
            let token_endpoint: String
        }

        var issuerBase = pds
        if let url = URL(string: "\(pds)/.well-known/oauth-protected-resource"),
           let (data, _) = try? await session.data(from: url),
           let protectedResource = try? JSONDecoder().decode(Protected.self, from: data),
           let first = protectedResource.authorization_servers?.first {
            issuerBase = first
        }

        guard let metadataURL = URL(string: "\(issuerBase)/.well-known/oauth-authorization-server") else {
            throw ATProtoError.invalidURL
        }
        let (data, _) = try await session.data(from: metadataURL)
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)

        guard let par = URL(string: metadata.pushed_authorization_request_endpoint),
              let authorize = URL(string: metadata.authorization_endpoint),
              let token = URL(string: metadata.token_endpoint) else {
            throw ATProtoError.invalidURL
        }
        return AuthorizationServer(issuer: metadata.issuer, parEndpoint: par,
                                   authorizationEndpoint: authorize, tokenEndpoint: token)
    }

    // MARK: - Authorization

    /// Pushes the request and returns the URL the browser should open.
    func authorizationURL(server: AuthorizationServer, key: DPoPKey, pkce: PKCE,
                          state: String, loginHint: String?) async throws -> URL {
        var form = [
            "client_id": OAuthConfig.clientID,
            "redirect_uri": OAuthConfig.redirectURI,
            "response_type": "code",
            "scope": OAuthConfig.scope,
            "state": state,
            "code_challenge": pkce.challenge,
            "code_challenge_method": "S256"
        ]
        if let loginHint, !loginHint.isEmpty { form["login_hint"] = loginHint }

        struct Response: Decodable { let request_uri: String }
        let data = try await post(form, to: server.parEndpoint, key: key, accessToken: nil)
        let response = try JSONDecoder().decode(Response.self, from: data)

        var components = URLComponents(url: server.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.clientID),
            URLQueryItem(name: "request_uri", value: response.request_uri)
        ]
        guard let url = components?.url else { throw ATProtoError.invalidURL }
        return url
    }

    func exchange(code: String, server: AuthorizationServer, key: DPoPKey, pkce: PKCE,
                  pds: String) async throws -> DPoPTokens {
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConfig.redirectURI,
            "client_id": OAuthConfig.clientID,
            "code_verifier": pkce.verifier
        ]
        return try await token(form: form, server: server, key: key, pds: pds)
    }

    func refresh(_ tokens: DPoPTokens, server: AuthorizationServer, key: DPoPKey) async throws -> DPoPTokens {
        guard let refreshToken = tokens.refreshToken else { throw ATProtoError.notAuthenticated }
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConfig.clientID
        ]
        return try await token(form: form, server: server, key: key, pds: tokens.pdsHost)
    }

    private func token(form: [String: String], server: AuthorizationServer,
                       key: DPoPKey, pds: String) async throws -> DPoPTokens {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let sub: String?
        }
        let data = try await post(form, to: server.tokenEndpoint, key: key, accessToken: nil)
        let response = try JSONDecoder().decode(Response.self, from: data)

        guard let did = response.sub else {
            throw ATProtoError.server(status: 400, error: "MissingSubject", message: nil)
        }
        return DPoPTokens(accessToken: response.access_token,
                          refreshToken: response.refresh_token,
                          did: did,
                          handle: nil,
                          issuer: server.issuer,
                          pdsHost: pds,
                          keyRaw: key.raw)
    }

    // MARK: - Transport

    /// Form post with a DPoP proof, retried once when the server demands a nonce.
    private func post(_ form: [String: String], to url: URL, key: DPoPKey,
                      accessToken: String?, isRetry: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(try key.proof(method: "POST", url: url, nonce: nonce, accessToken: accessToken),
                         forHTTPHeaderField: "DPoP")
        request.httpBody = Self.encodeForm(form)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ATProtoError.server(status: -1, error: nil, message: nil)
        }

        if let issued = http.value(forHTTPHeaderField: "DPoP-Nonce") { nonce = issued }

        if (200..<300).contains(http.statusCode) { return data }

        struct Failure: Decodable { let error: String?; let error_description: String? }
        let failure = try? JSONDecoder().decode(Failure.self, from: data)

        // The first call always fails this way: the server hands out the nonce here.
        if failure?.error == "use_dpop_nonce", !isRetry {
            return try await post(form, to: url, key: key, accessToken: accessToken, isRetry: true)
        }
        throw ATProtoError.server(status: http.statusCode,
                                  error: failure?.error,
                                  message: failure?.error_description)
    }

    private static func encodeForm(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = form.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
