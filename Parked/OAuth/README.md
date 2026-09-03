# OAuth — geparkt

Der AT-Protocol-OAuth-Flow ist vollständig gebaut, aber aus der App genommen,
solange keine öffentlich erreichbare `client-metadata.json` existiert. Ihre URL
*ist* die Client-ID; ohne sie kann der Flow nicht abschließen, und ein Weg, der
im Login sichtbar ist und dann scheitert, ist schlechter als keiner.

Diese Dateien liegen außerhalb von `Relays/`, damit Xcode sie nicht mitkompiliert.

## Was hier liegt

- `DPoP.swift` — P-256-Schlüssel, JWK-Thumbprint, Proof-JWTs (RFC 9449), PKCE
- `OAuthClient.swift` — Identity-Resolution, Metadaten, PAR, Token-Tausch
- `OAuthFlow.swift` — der Browser-Teil über `ASWebAuthenticationSession`

Alles davon war getestet, soweit es ohne Server prüfbar ist: Die Proof-JWTs
werden gegen ihren eigenen Public Key verifiziert, `htu` trägt keine Query,
`ath` ist der Token-Hash, PKCE-Challenge ist der S256-Hash des Verifiers.
Diese Tests liegen in `Parked/OAuth/OAuthTests.swift`.

## Zurückholen

1. Die drei Swift-Dateien nach `Relays/OAuth/` zurückschieben, die Tests nach
   `RelaysTests/`.
2. In `OAuthClient.swift` `OAuthConfig.clientID` auf die gehostete Datei zeigen
   lassen und `callbackScheme` auf deren Host in Reverse-DNS-Form setzen.
3. In `ATProtoClient` die DPoP-Teile wiederherstellen: ein `dpopKey`, der bei
   gesetztem Schlüssel `Authorization: DPoP …` samt `DPoP`-Proof-Header sendet,
   und die Wiederholung, wenn der Server per `DPoP-Nonce` eine Nonce nachreicht.
4. In `AppModel` den OAuth-Anmeldeweg und die Erneuerung wieder einhängen;
   `StoredSession.dpopKey` ist dafür noch da.
5. Im Login den zweiten Knopf wieder zeigen.

Die `client-metadata.json` muss enthalten, was `OAuthConfig.metadataDocument`
beschreibt.
