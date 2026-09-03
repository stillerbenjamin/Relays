//
//  DPoP.swift
//  Relays
//
//  AT Protocol OAuth binds every token to a key the client holds. Each request
//  carries a fresh proof JWT signed with that key (RFC 9449).
//

import Foundation
import CryptoKit

struct DPoPKey {
    let privateKey: P256.Signing.PrivateKey

    init() { privateKey = P256.Signing.PrivateKey() }

    init?(raw: Data) {
        guard let restored = try? P256.Signing.PrivateKey(rawRepresentation: raw) else { return nil }
        privateKey = restored
    }

    var raw: Data { privateKey.rawRepresentation }

    /// Public key as a JWK, which travels in the proof header.
    var jwk: [String: String] {
        let key = privateKey.publicKey.rawRepresentation   // x‖y, 32 bytes each
        return [
            "kty": "EC",
            "crv": "P-256",
            "x": Base64URL.encode(key.prefix(32)),
            "y": Base64URL.encode(key.suffix(32))
        ]
    }

    /// RFC 7638 thumbprint — the server ties the token to this value.
    var thumbprint: String {
        let ordered = #"{"crv":"P-256","kty":"EC","x":"\#(jwk["x"] ?? "")","y":"\#(jwk["y"] ?? "")"}"#
        return Base64URL.encode(Data(SHA256.hash(data: Data(ordered.utf8))))
    }

    /// A proof for one request. `nonce` comes from the server's DPoP-Nonce header,
    /// `accessToken` binds the proof to the token once there is one.
    func proof(method: String, url: URL, nonce: String?, accessToken: String?) throws -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let htu = components?.url?.absoluteString ?? url.absoluteString

        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": jwk
        ]

        var payload: [String: Any] = [
            "jti": UUID().uuidString,
            "htm": method.uppercased(),
            "htu": htu,
            "iat": Int(Date().timeIntervalSince1970)
        ]
        if let nonce { payload["nonce"] = nonce }
        if let accessToken {
            payload["ath"] = Base64URL.encode(Data(SHA256.hash(data: Data(accessToken.utf8))))
        }

        let headerPart = Base64URL.encode(try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let payloadPart = Base64URL.encode(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let signingInput = "\(headerPart).\(payloadPart)"

        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(Base64URL.encode(signature.rawRepresentation))"
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }
}

/// PKCE verifier and challenge (S256).
struct PKCE {
    let verifier: String
    var challenge: String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Base64URL.encode(Data(bytes))
    }
}
