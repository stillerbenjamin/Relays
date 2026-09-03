//
//  OAuthTests.swift
//  RelaysTests — parked alongside the OAuth code it covers.
//
//  Move back to RelaysTests/ when the flow returns to the app.
//

import Testing
import Foundation
import CryptoKit
@testable import Relays

// MARK: - OAuth primitives

/// The OAuth flow itself needs a hosted client-metadata.json to run end to end,
/// but its cryptography is testable here.
@Suite("OAuth primitives")
struct OAuthTests {

    @Test("Base64URL round-trips and drops padding")
    func base64url() throws {
        let data = Data([0xFB, 0xFF, 0x00, 0x10])
        let encoded = Base64URL.encode(data)
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(Base64URL.decode(encoded) == data)
    }

    @Test("PKCE challenge is the S256 hash of the verifier")
    func pkce() throws {
        let pkce = PKCE()
        #expect(pkce.verifier.count >= 43)
        let expected = Base64URL.encode(Data(SHA256.hash(data: Data(pkce.verifier.utf8))))
        #expect(pkce.challenge == expected)
    }

    @Test("A DPoP proof is a signed ES256 JWT the server can verify")
    func proofStructure() throws {
        let key = DPoPKey()
        let url = URL(string: "https://bsky.social/oauth/token?ignored=1")!
        let proof = try key.proof(method: "post", url: url, nonce: "n-1", accessToken: nil)

        let parts = proof.split(separator: ".").map(String.init)
        #expect(parts.count == 3)

        let header = try JSONSerialization.jsonObject(with: Base64URL.decode(parts[0])!) as? [String: Any]
        #expect(header?["typ"] as? String == "dpop+jwt")
        #expect(header?["alg"] as? String == "ES256")
        let jwk = header?["jwk"] as? [String: String]
        #expect(jwk?["crv"] == "P-256")
        #expect(Base64URL.decode(jwk?["x"] ?? "")?.count == 32)
        #expect(Base64URL.decode(jwk?["y"] ?? "")?.count == 32)

        let payload = try JSONSerialization.jsonObject(with: Base64URL.decode(parts[1])!) as? [String: Any]
        #expect(payload?["htm"] as? String == "POST")
        // The query string must not be part of htu.
        #expect(payload?["htu"] as? String == "https://bsky.social/oauth/token")
        #expect(payload?["nonce"] as? String == "n-1")
        #expect(payload?["ath"] == nil)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Base64URL.decode(parts[2])!)
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        #expect(key.privateKey.publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test("Binding a token adds its hash to the proof")
    func tokenBinding() throws {
        let key = DPoPKey()
        let proof = try key.proof(method: "GET", url: URL(string: "https://example.com/xrpc/a")!,
                                  nonce: nil, accessToken: "token-abc")
        let parts = proof.split(separator: ".").map(String.init)
        let payload = try JSONSerialization.jsonObject(with: Base64URL.decode(parts[1])!) as? [String: Any]
        #expect(payload?["ath"] as? String == Base64URL.encode(Data(SHA256.hash(data: Data("token-abc".utf8)))))
    }

    @Test("A stored key survives the round trip through the keychain blob")
    func keyPersistence() throws {
        let key = DPoPKey()
        let restored = DPoPKey(raw: key.raw)
        #expect(restored?.thumbprint == key.thumbprint)
    }
}

