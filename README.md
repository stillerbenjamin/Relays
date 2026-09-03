# Relays

A Bluesky client for iOS and macOS that shows you the network underneath.

The AT Protocol is not one service. It is many servers, many moderation services
and one open stream, and almost no client lets you see which of them you are
talking to. Relays does: the server hosting each post, the service that labelled
it, and the firehose itself, running behind the wordmark.

Written in Swift 5 with SwiftUI and Observation, against 66 protocol endpoints
directly. No SDK, no backend of its own, no third-party code of any kind.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Building and running](#building-and-running)
- [Tests](#tests)
- [How the project is laid out](#how-the-project-is-laid-out)
- [Design decisions worth knowing](#design-decisions-worth-knowing)
- [What is not finished](#what-is-not-finished)
- [Parked code](#parked-code)
- [Tools](#tools)
- [Licence](#licence)

---

## What it does

### Reading

Following timeline, saved feeds and lists in one switcher; threads with the whole
chain of parents; search across accounts, posts and hashtags; the posts that quote
a given post. The search screen opens on discovery — feeds other people keep and
accounts the network suggests — rather than on a hint. Yesterday's page appears
from a local cache while today's loads.

### Posting

Up to four pictures with alt text, or one video through Bluesky's video service.
Links, hashtags and mentions are detected as you type and indexed in **UTF-8
bytes**, which is how the protocol counts them. Quotes, replies, reposts, deleting
your own posts.

A link in the text becomes a card: Relays reads the page's own Open Graph
tags, uploads the picture and attaches an `app.bsky.embed.external` — reading
the page directly rather than handing every URL you type to a card service.

Per post, before it exists: **who may reply** (everyone, people you follow, people
you mention, your followers, nobody) and **whether it may be quoted**. Both are
records in your own repository, so they hold in every client. In a thread you
started, a reply can be folded away — hidden for everyone reading it, still there
in the network.

### Moderation

Built in six layers over the protocol's own model:

| Layer | What it does |
|---|---|
| Truth from the server | Mutes, blocks and preferences are read at sign-in, not gathered from profiles you happen to meet |
| The decision | Every post gets one verdict — hide, cover, blur media, warn, badge, allow — with the reason and its source |
| Moderation services | Subscribe to any labeler; set each of its labels to show, warn or hide |
| Words and lists | Muted words with targets, expiry and an exception for people you follow; mute and block lists, subscribed or your own |
| Your own space | Reply and quote rules, hidden posts, folded replies |
| Messages and reports | Who may message you, muting and leaving conversations, and reports addressed to a service you chose |

Anything covered says **which layer decided it** and names the service if a
service did. Local feed rules — regular expressions, domains, handles,
self-hosted-only — stay on the device and are never uploaded.

### Messages

Conversations, history, starting one from a search, muting and leaving, reporting
a single message, and a setting for who may write to you at all.

### The relay

The hairline under the wordmark is the firehose: every record on the network as
it is written, brighter where more was written. Tapping the title opens the
readings — throughput, median latency from the author's timestamp to arrival,
composition, and a sampled ranking of servers with the share that are
self-hosted.

Behind that sits the relay's own **register**: not a sample but the roll — every
server it reads from, with account counts and whether each is up. When this was
written that was 6 156 servers, of which 89 are Bluesky's; 552 880 accounts live
on the other 6 067. The sample says who is writing right now; the register says
who exists. Both are shown, and both are labelled.

The sign-in screen's backdrop is the same stream, running before anybody has
signed in to anything — and under the handle field, before any password is
typed, the screen names **the server that handle actually lives on** and what the
relay currently thinks of it. That answer is public: a handle resolves to a DID,
the DID document names the server. No other client says it out loud.

### Provenance

The hosting server printed under every post. A record inspector showing the raw
JSON, DID, CID, AT URI and facets of any post. Your whole repository exportable
as a signed CAR file.

### The app itself

Four grounds (light, dim, dark, Bluesky blue), two languages (English, German),
three text sizes plus the system size up to 145 %, VoiceOver throughout, several
accounts switched without signing out, and an honest offline state that says the
connection is gone rather than blaming the server.

---

## Requirements

| | |
|---|---|
| Xcode | 16.4 or newer |
| iOS | 18.5 |
| macOS | 15.5 |
| Swift | 5 language mode (see [Swift 6](#swift-6)) |
| Dependencies | none |

There is nothing to install. No package manager, no `pod install`, no
`Package.resolved` — the project builds from a clone.

---

## Building and running

```bash
open Relays.xcodeproj
```

Pick the **Relays** scheme and run. From the command line:

```bash
xcodebuild -project Relays.xcodeproj -scheme Relays \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

macOS is a first-class target and builds from the same scheme:

```bash
xcodebuild -project Relays.xcodeproj -scheme Relays \
  -destination 'platform=macOS' build
```

### Two things to change first

The project carries its author's signing settings, and neither of them will work
for anybody else:

| Setting | Where | Why |
|---|---|---|
| `DEVELOPMENT_TEAM` | Target → Signing & Capabilities → Team | Pick your own, including a free personal Apple ID |
| `PRODUCT_BUNDLE_IDENTIFIER` | same panel, Bundle Identifier | App IDs are unique across all of Apple's developer accounts, and `com.stillerbenjamin.Relays` is taken. Use your own reverse-domain name |

A **free Apple ID is enough** to build and run this. The app asks for nothing a
free account cannot sign: the sandbox, outgoing network, and read access to a
file the reader picked themselves. There is no push entitlement, no app group,
no capability that needs a paid membership.

What a free account does limit is how long the result lives. On iOS the
provisioning profile expires after **seven days**, after which the app stops
launching until it is built again — that is Apple's rule for free accounts, not
something about this project. On **macOS a locally built app runs
indefinitely**.

### Handing the built app to somebody else

Cloning and building is free. Passing a finished binary around is not:

| | Needs the Developer Program |
|---|---|
| Clone the repository and build it yourself | no |
| Run your own build on your own Mac | no |
| Run your own build on your own iPhone, seven days at a time | no |
| Send somebody a Mac app that opens without a Gatekeeper warning | yes — Developer ID and notarisation |
| Send somebody an iPhone build (TestFlight, ad hoc, App Store) | yes |

A Mac app signed with a free account and downloaded from the internet is
quarantined: it opens only through right-click → Open, or after
`xattr -d com.apple.quarantine Relays.app`. That is a warning about the
signature, not about the app, and it is the honest reason to keep this a
source-only release for now.

### Signing in

Relays signs in with an **app password**, not your account password. Make one in
your Bluesky account settings and use it here; it can be revoked without touching
your account. You are never asked which server your account lives on — the app
resolves the handle through the PLC directory or the domain itself and talks to
whatever it finds, so self-hosted accounts work like any other.

To use direct messages the app password needs **message access**, which is a
separate checkbox when you create it. An ordinary one cannot read messages, and
the app says so rather than showing an error.

---

## Tests

```bash
xcodebuild test -project Relays.xcodeproj -scheme Relays \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled NO
```

**267 unit tests** in 64 suites, plus **4 UI tests**. `-parallel-testing-enabled NO`
matters twice over: the layout snapshots write into the host app's documents
directory, and a parallel clone's container is thrown away before the files can
be collected — and the stub transport is one shared queue, which parallel suites
scramble. Without the flag around forty tests fail for no reason of their own.

The same suites run on macOS, where 262 of them apply — picture attachment is a
UIKit path with nothing on the other side, and one snapshot is macOS-only:

```bash
xcodebuild test -project Relays.xcodeproj -scheme Relays \
  -destination 'platform=macOS' -only-testing:RelaysTests \
  -parallel-testing-enabled NO
```

The **UI tests are iOS only**. They drive the sign-in screen through the iOS
chrome and fail against a Mac window; `-only-testing:RelaysTests` is the whole
of the macOS run.

### The three kinds

**Stub transport.** Most tests drive `ATProtoClient` through a `URLProtocol` stub
that answers queued replies, matched by request path where calls go out
concurrently. This covers request shape, header handling, token refresh, rate
limits, error decoding and the whole moderation decision engine.

**Layout snapshots.** `RelaysTests/LayoutSnapshots.swift` renders real views with
fixed sample data through `ImageRenderer` and writes PNGs into the host app's
documents directory. This is how a layout can be looked at without an account.
Note the renderer's limits: `LazyVStack`, `ScrollView`, `TextEditor` and `Menu`
do not draw, so views under test are composed eagerly and menus appear as
placeholder glyphs.

**Live suites, disabled by default.** Nine suites talk to the real network. They
need no account — everything they touch is public — but they need connectivity,
so they do not run with the rest:

| Suite | What it checks |
|---|---|
| Relay against the live firehose | Records actually arrive and decode, latency is plausible |
| Labelers against the live network | A real service's policies and definitions; labels fetched straight from a labeler |
| Lists against the live network | A real moderation list and its members |
| Discovery against the live network | Popular feeds come back with what the row needs |
| Post lists against the live network | Likes and reposts answer, each in its own shape |
| The register against the live network | A relay hands out its host register |
| The sign-in lookup against the live network | A handle resolves to the server it lives on |
| Servers describing themselves, live | What real servers require of a new account |
| Link cards against the live network | The project's own page reads as a card |

Run one by name after touching the code it covers:

```bash
xcodebuild test -project Relays.xcodeproj -scheme Relays \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RelaysTests/LabelerLiveTests
```

### A note about Previews

Running `xcodebuild test` leaves the test bundle and the XCTest frameworks
embedded in the built app. Xcode Previews launches that same product and cannot
start it, reporting **"Failed to launch com.stillerbenjamin.Relays"**. A plain
build (⌘B) puts a clean product back. This is not a project misconfiguration —
the app target embeds nothing — it is the test and app builds sharing one
output directory.

---

## How the project is laid out

```
Relays/
  ATProto/     16 files, 5 700 lines — the protocol: client, models, moderation,
               sign-up, preferences, firehose, DID resolution
  App/         10 files, 1 800 lines — settings, localisation, notifications,
               background refresh, reachability, formatting
  Design/       5 files,   800 lines — theme, components, fonts, the login backdrop
  Features/    31 files, 8 200 lines — every screen
  Resources/                          Inter
  PrivacyInfo.xcprivacy               the App Store privacy manifest
Config/Info.plist                     what build settings cannot express
RelaysTests/   16 files, 4 700 lines
RelaysUITests/                        smoke tests, everything before sign-in
Parked/                               written, not shipped
Tools/                                the app icon generator
```

The project uses Xcode 16's **file-system synchronized groups**: anything under
`Relays/` is compiled automatically, and `Parked/` and `Tools/` deliberately sit
outside it. Adding a file means creating it; there is nothing to register.

### The shape of it

`ATProtoClient` is an **actor** holding the session and the service host. Every
call goes through one `perform` that adds authentication, the
`atproto-accept-labelers` header, and the `atproto-proxy` header where a call is
addressed to another service. It retries once on an expired token and once on a
short rate limit, and it ends the session when a credential has been revoked
rather than offering a retry that cannot succeed.

`AppModel` is `@MainActor @Observable` and holds everything a screen reads:
session, per-post state, follow state, moderation state, preferences. Views take
it from the environment. There are four environment objects in total —
`AppModel`, `AppSettings`, `NotificationService`, `Reachability` — and
`previewEnvironment()` in `RelaysApp.swift` installs all four, so a preview cannot
miss one.

---

## Design decisions worth knowing

**Facets are counted in UTF-8 bytes.** Every link, mention and hashtag range is a
byte offset, not a character offset. Getting this wrong is invisible until
somebody writes an emoji before a link.

**The preferences record is never written blind.** `putPreferences` replaces the
whole array, which also holds another client's saved feeds, muted words and birth
date. `Preferences` carries every entry it does not model through untouched, and
`AppModel` refuses to write a record it never successfully read.

**Moderation resolves to one verdict.** The strictest wins, and the device can
only ever be stricter than the network — otherwise the result would depend on the
order labels happen to arrive in.

**Labels reach the app two ways.** The `atproto-accept-labelers` header asks the
appview for them, and every labeler also answers for its own labels directly and
unauthenticated. Both are implemented, because the header path could not be
confirmed from outside a session.

**Nothing is measured.** No analytics, no crash reporter, no advertising
identifier, no third-party library. `PrivacyInfo.xcprivacy` declares one
required-reason API (`UserDefaults`, reason `CA92.1`) and the data the app carries
on the reader's behalf.

<a name="swift-6"></a>
**Swift 5 language mode.** The project builds warning-free at its own strictness.
Under `SWIFT_STRICT_CONCURRENCY=complete` there are 44 remaining diagnostics —
mutable globals (`L10n.language`, `Theme`), the `EnvironmentKey` default values,
and `NotificationService`. Moving to Swift 6 means deciding those deliberately,
not silencing them.

---

## What is not finished

Stated plainly, because a repository that hides this wastes the next person's
afternoon.

**No write path has ever run against a real account.** Posting, liking, following,
reporting, blocking, uploading, moderation settings, threadgates, lists,
sign-up — all of it is verified against a stubbed transport and none of it against
a live server. This is the largest open risk in the project and an hour with a
real account is worth more than any further test.

**Not submitted to the App Store.** The privacy manifest is in place and the
moderation features a submission requires are built. What is missing is
paperwork: a hosted privacy policy and support address, terms, an age rating and
screenshots.

**Notifications have no push service.** The app checks in the background and
delivers what it finds; how often iOS grants it a turn is up to iOS. Real push
would need a service watching the firehose and an APNs certificate — so the
`remote-notification` background mode is deliberately not declared, and a test
checks that no mode is claimed that the app cannot honour.

**Notification preferences now live on the account, unproven.** Twelve kinds,
each with two switches and — for eight of them — an audience, read and written
through `app.bsky.notification.getPreferences` and `putPreferencesV2`. The wire
shape is pinned by tests, including the part that is easy to get wrong: four of
the twelve must not carry an audience and eight must. Whether the server accepts
the body has never been observed, because every notification endpoint needs an
account.

The four device-local switches this replaces are carried up once, and only their
alert half — they never governed what appeared in the list, and writing them
there would have hidden things on every other client.

**Video upload is fixed but unproven end to end.** The job is now polled on the
video service rather than on the account's own server, which is why uploads never
completed before. Whether the service accepts the token has not been observed.

---

## Parked code

`Parked/` holds work that is finished but cannot ship yet. It is outside the
compiled group, and each directory has a README explaining what it is and how to
bring it back.

**`Parked/OAuth/`** — DPoP, the client and the flow. It needs one thing: a
publicly reachable `client-metadata.json`, whose URL *is* the client ID. Until
there is a domain, the app uses app passwords.

**`Parked/SignUp/`** — making an account: the server-driven form, 248 dialling
codes, the E.164 handling, the tests. Not broken — unusable. `bsky.social`
answers `describeServer` with `phoneVerificationRequired: true` and then refuses
every request for a code with `phone verification not enabled`. A form nobody can
finish is worse than no form.

---

## Tools

`Tools/MakeIcon.swift` generates the app icon set — the Inter "R", black on
Bluesky blue, in every size iOS and macOS ask for:

```bash
swift Tools/MakeIcon.swift Relays/Assets.xcassets/AppIcon.appiconset
```

---

## Licence

[MIT](LICENSE). Do what you like with it; leave the notice in.

The bundled copy of **Inter** in `Relays/Resources/` is not covered by that.
It is Rasmus Andersson's, under the
[SIL Open Font License 1.1](https://github.com/rsms/inter/blob/master/LICENSE.txt),
which asks that the licence travel with the font — see
`Relays/Resources/Inter-LICENSE.txt`.

---

Relays is built on the AT Protocol and is not affiliated with Bluesky Social PBC.
