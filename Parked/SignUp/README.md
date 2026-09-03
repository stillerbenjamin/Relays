# Kontoerstellung

Fertig gebaut, geprüft, und bewusst nicht ausgeliefert.

## Was hier liegt

| Datei | Was sie ist |
|---|---|
| `SignUpView.swift` | Das Formular. Baut sich aus dem, was `describeServer` sagt: Einladungsfeld nur wo eines verlangt wird, Telefonschritt nur wo der Server so prüft |
| `SignUp.swift` | `SignUpDraft` — die Felder, die E.164-Umwandlung, und ob es reicht |
| `DiallingCodes.swift` | 248 Länder, ISO-Code auf ITU-Vorwahl, aus dem `mledoze/countries`-Datensatz erzeugt |
| `DiallingCodeField.swift` | Das kleine Fenster am Telefonfeld, mit Suche |
| `SignUpTests.swift`, `PhoneTests.swift` | Die Tests dazu |
| `SignUpSnapshot.swift.txt` | Der Snapshot, der aus `LayoutSnapshots` herausgenommen wurde |
| `Strings.txt` | Die 29 Schlüssel und 58 Übersetzungszeilen aus `L10n.swift` |

## Warum es geparkt ist

Nicht weil es kaputt wäre. Weil bsky.social sich selbst widerspricht:

```
describeServer           → "phoneVerificationRequired": true
requestPhoneVerification → 400  "phone verification not enabled"
```

Der Server verlangt im Deskriptor eine Telefonnummer und lehnt dann jede Anfrage
nach einem Code ab — geprüft mit drei Nummern aus drei Ländern, immer dieselbe
Antwort. Ein Formular, das niemand abschließen kann, ist schlechter als kein
Formular.

`app.bsky.contact.startPhoneVerification` sieht aus wie der Nachfolger, ist es
aber nicht: das Lexikon verlangt dort Authentifizierung, es gehört zum
Kontaktimport nach der Anmeldung.

## Zurückholen

1. Die vier Swift-Dateien nach `Relays/Features/`, `Relays/ATProto/`,
   `Relays/App/` und `Relays/Design/` zurück, die zwei Testdateien nach
   `RelaysTests/`.
2. `Strings.txt` zurück in `L10n.swift` — Schlüssel in die Aufzählung, Zeilen in
   **beide** Tabellen.
3. In `ATProtoClient.swift` unter `// MARK: - Asking a server about itself` diese
   drei Methoden wieder einsetzen (sie brauchen das private `send`, können also
   nicht hier liegen):
   - `isHandleFree(_:host:)` — `com.atproto.identity.resolveHandle`, statisch,
     unauthentifiziert
   - `requestPhoneVerification(phone:)` — `com.atproto.temp.requestPhoneVerification`
   - `createAccount(handle:email:password:inviteCode:phone:phoneCode:)` —
     `com.atproto.server.createAccount`, `authenticated: false`, setzt die
     zurückgegebene Sitzung
4. `AppModel.signUp(draft:description:)` wieder einsetzen: Konto anlegen, sofort
   ein eigenes App-Passwort erzeugen, nur damit weiterarbeiten, Geburtsdatum in
   die Preferences schreiben.
5. In `AuthGateView.swift` den zweiten Weg wieder einhängen — `showsSignUp` am
   `SignInForm`, das Blatt, und die Zeile „Noch kein Konto?".
6. Die zwei UI-Tests wieder einsetzen, die durch diese Tür gingen
   (`testSignUpSheetOpensOnTheDefaultServer`, `testSignUpSaysWhenAServerDoesNotAnswer`).

`ServerDescription` ist **nicht** mit hier: die Struktur ist nach
`Relays/ATProto/ATProtoModels.swift` gewandert, weil `describeServer` unabhängig
von der Registrierung nützlich bleibt. Beim Zurückholen also nicht doppelt
anlegen.
