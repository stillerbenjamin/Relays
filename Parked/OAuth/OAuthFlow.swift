//
//  OAuthFlow.swift
//  Relays
//
//  Drives the browser leg of the OAuth flow.
//

import Foundation
import AuthenticationServices

@MainActor
final class OAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let client = OAuthClient()

    /// Runs discovery, PAR, the browser round trip and the token exchange.
    func signIn(identifier: String) async throws -> DPoPTokens {
        let discovery = try await client.discover(identifier: identifier)
        let key = DPoPKey()
        let pkce = PKCE()
        let state = UUID().uuidString

        let url = try await client.authorizationURL(server: discovery.server, key: key, pkce: pkce,
                                                    state: state, loginHint: identifier)
        let callback = try await present(url)

        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            let error = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error_description" })?.value
            throw ATProtoError.server(status: 400, error: "AuthorizationFailed", message: error)
        }
        guard components.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw ATProtoError.server(status: 400, error: "StateMismatch", message: nil)
        }

        var tokens = try await client.exchange(code: code, server: discovery.server,
                                               key: key, pkce: pkce, pds: discovery.pds)
        tokens.handle = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return tokens
    }

    /// Refreshes a DPoP-bound session against the account's authorization server.
    func refresh(_ tokens: DPoPTokens) async throws -> DPoPTokens {
        guard let key = DPoPKey(raw: tokens.keyRaw) else { throw ATProtoError.notAuthenticated }
        let discovery = try await client.discover(identifier: tokens.did)
        return try await client.refresh(tokens, server: discovery.server, key: key)
    }

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuthConfig.callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? ATProtoError.notAuthenticated)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
