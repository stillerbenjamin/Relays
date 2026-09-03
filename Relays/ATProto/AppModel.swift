//
//  AppModel.swift
//  Relays
//

import Foundation
import Observation

/// Per-post state that changes through interaction. Held centrally so the timeline,
/// thread and profile screens all show the same truth.
struct PostState: Equatable {
    var likeUri: String?
    var repostUri: String?
    var likeCount: Int
    var repostCount: Int
    var replyCount: Int
    var quoteCount: Int

    init(post: PostView) {
        likeUri = post.viewer?.like
        repostUri = post.viewer?.repost
        likeCount = post.likeCount ?? 0
        repostCount = post.repostCount ?? 0
        replyCount = post.replyCount ?? 0
        quoteCount = post.quoteCount ?? 0
    }

    var isLiked: Bool { likeUri != nil }
    var isReposted: Bool { repostUri != nil }

    /// What the repost control counts. A quote is a repost with something added,
    /// and the network counts the two separately — a reader who quotes and then
    /// sees no number move has no way to tell it worked.
    var sharedCount: Int { repostCount + quoteCount }
}

@MainActor
@Observable
final class AppModel {

    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var session: ATSession?
    private(set) var profile: ActorProfile?
    private(set) var unreadNotifications: Int = 0

    /// Navigation state lives here so a font or language change does not reset it.
    var selectedTab: Tab = .timeline
    /// Rises each time the tab already showing is tapped again. The screen it
    /// belongs to takes that as: back to the top, and fetch.
    private(set) var reselects: [Tab: Int] = [:]
    var profileSection: ProfileSection = .posts

    /// Interaction state keyed by post URI.
    private(set) var postStates: [String: PostState] = [:]
    /// Follow record URI per account DID; nil means not following.
    private(set) var followStates: [String: String?] = [:]
    /// Everyone the account has muted or blocked, loaded from the server at
    /// sign-in rather than gathered from whichever profiles happen to come past.
    private(set) var mutedActors: Set<String> = []
    private(set) var blockedActors: [String: String] = [:]
    /// Lists the account mutes wholesale. Individual members arrive with
    /// `mutedByList` on their viewer state; this is only the count.
    private(set) var mutedLists: [String] = []

    /// The account's preferences, carried through whole on every write.
    private(set) var preferences = Preferences()
    /// Whether the array above actually came from the server. Writing one that
    /// was never read would replace every entry this app does not model —
    /// saved feeds, muted words, a birth date — with nothing.
    private(set) var preferencesAreLoaded = false
    /// Moves whenever a moderation setting changes, so cached decisions expire.
    private(set) var moderationToken = 0
    /// Posts the reader chose to uncover, for as long as the app is running.
    private(set) var revealed: Set<String> = []
    /// Posts removed in this session; feeds filter them out at once.
    private(set) var deletedPosts: Set<String> = []

    let client: ATProtoClient
    let directory = PDSDirectory()
    let profileCache = ProfileCache()
    let rules = FeedRules()

    /// The firehose behind the wordmark. Idle until a view asks for it.
    let relay: RelayMonitor

    /// Moderation services the account subscribes to.
    let labelers = LabelerDirectory()
    /// What the server said it applies, whether or not it was asked to.
    private(set) var appliedLabelers: [String] = []

    /// Every signed-in account, across servers.
    private(set) var accounts: [StoredSession] = []

    /// `configuration` exists for tests; the app uses the default transport.
    init(configuration: URLSessionConfiguration? = nil) {
        client = ATProtoClient(configuration: configuration)
        relay = RelayMonitor(directory: directory)
    }

    #if DEBUG
    /// Puts the model into a signed-in state without touching the network.
    /// Only used by tests; there is no path to it from the app.
    /// Seams for the tests that cover a credential dying under the app.
    func installSessionObserverForTesting() async { await installSessionObserver() }
    func loadModerationForTesting() async { await loadModeration() }

    func useTestSession() async {
        let test = ATSession(accessJwt: "test", refreshJwt: "test", handle: "tester.test",
                             did: "did:plc:tester", email: nil, service: "https://pds.test")
        await client.setService("https://pds.test")
        await client.setSession(test)
        session = test
        phase = .signedIn
    }
    #endif

    // MARK: - Launch

    func bootstrap() async {
        let store = AccountsStore.load()
        accounts = store.accounts
        guard let stored = store.active else {
            await finishLaunch(.signedOut)
            return
        }

        // Sessions from the parked OAuth path cannot be renewed while it is out of
        // the app; those accounts sign in again rather than failing silently later.
        guard !stored.isOAuth else {
            AccountsStore.clear()
            accounts = []
            await finishLaunch(.signedOut)
            return
        }

        await client.setService(stored.service)
        await client.setSession(stored.session)
        await installSessionObserver()
        session = stored.session

        do {
            _ = try await client.refreshSession()
            phase = .signedIn
            await loadOwnProfile()
            // Signing in and switching accounts both loaded this; a cold launch
            // with a stored session did not. So every fresh start began with an
            // empty mute list, no blocks, no subscribed labelers and unloaded
            // preferences — and `write(_:)` refuses to write preferences it
            // never read, so saved feeds and muted words could not be changed
            // either until something else happened to trigger a load.
            await loadModeration()
            await refreshUnreadCount()
        } catch ATProtoError.transport {
            // Offline: keep using the stored session. Moderation stays as the
            // last run left it rather than being wrongly empty.
            phase = .signedIn
            await loadOwnProfile()
        } catch {
            AccountsStore.clear()
            accounts = []
            await finishLaunch(.signedOut)
        }
    }

    private func finishLaunch(_ phase: Phase) async {
        self.phase = phase
    }

    // MARK: - Sign-in

    /// The server is looked up from the handle. Nobody should have to know where
    /// their account lives — the network does, and says so publicly.
    func signIn(identifier: String, appPassword: String,
                service: String? = nil) async throws {
        var discovered = service
        if discovered == nil {
            discovered = await PDSDirectory.resolveService(for: identifier)
        }
        let host = ATProtoClient.normalizeService(discovered ?? ATProtoClient.defaultService)
        await client.setService(host)
        await installSessionObserver()

        let newSession = try await client.createSession(identifier: identifier, password: appPassword)
        session = newSession
        store(session: newSession, service: host)
        resetPerAccountState()
        phase = .signedIn
        await loadOwnProfile()
        await loadModeration()
        await refreshUnreadCount()
    }

    // MARK: - Making an account


    /// Removes the account from the network. Everything it holds goes with it.
    func deleteAccount(password: String, token: String) async throws {
        guard let did = session?.did else { throw ATProtoError.notAuthenticated }
        try await client.deleteAccount(did: did, password: password, token: token)
        await signOut()
    }

    func requestAccountDeletion() async throws {
        try await client.requestAccountDelete()
    }

    /// Signs out of the active account; another stored account takes over if there is one.
    /// True while a deliberate sign-out is running. `logout()` reports the
    /// session going away through the same handler that catches a revoked one —
    /// without this, signing out would call itself.
    private var isSigningOut = false

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        let leaving = session?.did
        await client.logout()

        accounts.removeAll { $0.session.did == leaving }
        resetPerAccountState()

        if let next = accounts.first {
            AccountsStore.save(StoredAccounts(accounts: accounts, activeDID: next.session.did))
            await activate(next)
        } else {
            AccountsStore.clear()
            session = nil
            profile = nil
            phase = .signedOut
        }
    }

    /// Switches to another stored account without a round trip through the login screen.
    func switchTo(did: String) async {
        guard let target = accounts.first(where: { $0.session.did == did }),
              target.session.did != session?.did else { return }
        AccountsStore.save(StoredAccounts(accounts: accounts, activeDID: did))
        resetPerAccountState()
        await activate(target)
    }

    private func activate(_ stored: StoredSession) async {
        await client.setService(stored.service)
        await client.setSession(stored.session)
        session = stored.session
        phase = .signedIn
        _ = try? await client.refreshSession()
        await loadOwnProfile()
        await loadModeration()
        await refreshUnreadCount()
    }

    private func resetPerAccountState() {
        FeedCache.clear()
        postStates.removeAll()
        followStates.removeAll()
        mutedActors.removeAll()
        blockedActors.removeAll()
        mutedLists.removeAll()
        ownLists.removeAll()
        subscribedLists.removeAll()
        replyRules.removeAll()
        quotesAllowed.removeAll()
        messageRule = .all
        notificationPreferences = .defaults
        notificationPreferencesAreLoaded = false
        revealed.removeAll()
        labelers.forget()
        preferences = Preferences()
        preferencesAreLoaded = false
        moderationToken += 1
        decisionCache.removeAll()
        deletedPosts.removeAll()
        unreadNotifications = 0
        profile = nil
    }

    private func installSessionObserver() async {
        await client.setSessionChangeHandler { [weak self] updated in
            guard let self else { return }
            Task { @MainActor in
                guard let updated else {
                    // The credential died under us. Signing out is the only
                    // honest answer — every screen would otherwise keep offering
                    // a retry that cannot succeed.
                    guard !self.isSigningOut else { return }
                    await self.signOut()
                    return
                }
                self.session = updated
                self.store(session: updated, service: updated.service)
            }
        }
    }

    // MARK: - Profile and badges

    func loadOwnProfile() async {
        guard let did = session?.did else { return }
        profile = try? await client.profile(actor: did)
    }

    func refreshUnreadCount() async {
        unreadNotifications = (try? await client.unreadCount()) ?? unreadNotifications
    }

    /// Fetches notifications and hands anything new to the notification service.
    /// Used by the background task and when the app comes forward.
    func checkForNotifications(delivering service: NotificationService,
                               settings: AppSettings) async {
        guard phase == .signedIn else { return }
        service.use(account: session?.did)
        guard let response = try? await client.notifications(limit: 25) else { return }

        await service.deliver(response.notifications,
                              kinds: notificationPreferences, settings: settings)
        // The count comes from the server, not from counting a page. Counting
        // the unread inside a fetch of 25 capped the badge at 25 — and it
        // overwrote the accurate figure every two minutes.
        await refreshUnreadCount()
        await service.setBadge(unreadNotifications)
    }

    /// Marks everything seen, on the server and here. Called from the tab bar
    /// and from a tapped banner — a banner used to bypass this entirely, so the
    /// dot survived being read.
    func markNotificationsRead(badging service: NotificationService? = nil) async {
        guard phase == .signedIn else { return }
        do {
            try await client.markNotificationsSeen()
        } catch {
            // The server did not accept it, so the count is still true. Clearing
            // it here would make the dot vanish and come back on the next poll.
            return
        }
        unreadNotifications = 0
        await service?.setBadge(0)
    }

    // MARK: - Post state

    func register(_ posts: [PostView]) {
        for post in posts {
            if postStates[post.uri] == nil {
                postStates[post.uri] = PostState(post: post)
            }
            register(moderationOf: post.author)
        }
    }

    func reselect(_ tab: Tab) {
        reselects[tab, default: 0] += 1
    }

    func state(for post: PostView) -> PostState {
        postStates[post.uri] ?? PostState(post: post)
    }

    func toggleLike(_ post: PostView) async {
        var state = state(for: post)
        let previous = state

        if let likeUri = state.likeUri {
            state.likeUri = nil
            state.likeCount = max(0, state.likeCount - 1)
            postStates[post.uri] = state
            do { try await client.deleteRecord(uri: likeUri) }
            catch { postStates[post.uri] = previous }
        } else {
            state.likeUri = "pending"
            state.likeCount += 1
            postStates[post.uri] = state
            do {
                let response = try await client.like(uri: post.uri, cid: post.cid)
                postStates[post.uri]?.likeUri = response.uri
            } catch {
                postStates[post.uri] = previous
            }
        }
    }

    func toggleRepost(_ post: PostView) async {
        var state = state(for: post)
        let previous = state

        if let repostUri = state.repostUri {
            state.repostUri = nil
            state.repostCount = max(0, state.repostCount - 1)
            postStates[post.uri] = state
            do { try await client.deleteRecord(uri: repostUri) }
            catch { postStates[post.uri] = previous }
        } else {
            state.repostUri = "pending"
            state.repostCount += 1
            postStates[post.uri] = state
            do {
                let response = try await client.repost(uri: post.uri, cid: post.cid)
                postStates[post.uri]?.repostUri = response.uri
            } catch {
                postStates[post.uri] = previous
            }
        }
    }

    // MARK: - Following

    func register(_ profile: ActorProfile) {
        guard followStates[profile.did] == nil else { return }
        followStates[profile.did] = profile.viewer?.following
    }

    func isFollowing(_ profile: ActorProfile) -> Bool {
        (followStates[profile.did] ?? profile.viewer?.following) != nil
    }

    /// Optimistic like the post actions: the button answers at once and steps
    /// back if the write fails.
    func toggleFollow(_ profile: ActorProfile) async {
        guard profile.did != session?.did else { return }
        let previous = followStates[profile.did] ?? profile.viewer?.following

        if let existing = previous {
            followStates[profile.did] = String?.none
            do { try await client.deleteRecord(uri: existing) }
            catch { followStates[profile.did] = previous }
        } else {
            followStates[profile.did] = "pending"
            do {
                let response = try await client.follow(did: profile.did)
                followStates[profile.did] = response.uri
            } catch {
                followStates[profile.did] = String?.none
            }
        }
    }

    // MARK: - Moderation

    /// Mutes, blocks and preferences, from the server. Without this the app only
    /// knows about a mute if it happens to meet that profile — so a mute made on
    /// another client would not hold here.
    func loadModeration() async {
        guard session != nil else { return }

        async let mutes = try? client.mutes()
        async let blocks = try? client.blocks()
        async let lists = try? client.listMutes()
        async let stored = try? client.preferences()

        if let mutes = await mutes {
            mutedActors = Set(mutes.actors.map(\.did))
            profileCache.store(mutes.actors)
        }
        if let blocks = await blocks {
            blockedActors = blocks.actors.reduce(into: [:]) { result, actor in
                result[actor.did] = actor.viewer?.blocking ?? "blocked"
            }
            profileCache.store(blocks.actors)
        }
        if let lists = await lists { mutedLists = lists }
        if let stored = await stored {
            preferences = stored
            preferencesAreLoaded = true
        }

        await labelers.setSubscribed(preferences.subscribedLabelers, client: client)
        appliedLabelers = await client.appliedLabelers
        await loadMessageRule()
        await loadNotificationPreferences()

        moderationToken += 1
        decisionCache.removeAll()
    }

    // MARK: Muted words

    var mutedWords: [MutedWord] { preferences.mutedWordList }

    func addMutedWord(_ word: MutedWord) async {
        let trimmed = word.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = preferences
        var next = word
        next.value = trimmed
        updated.setMutedWords(preferences.mutedWordList + [next])
        await write(updated)
    }

    func removeMutedWord(_ word: MutedWord) async {
        var updated = preferences
        updated.setMutedWords(preferences.mutedWordList.filter { $0.id != word.id })
        await write(updated)
    }

    // MARK: One's own space

    var hiddenPosts: Set<String> { Set(preferences.hiddenPostURIs) }

    func toggleHidden(_ post: PostView) async {
        var uris = preferences.hiddenPostURIs
        if let index = uris.firstIndex(of: post.uri) { uris.remove(at: index) }
        else { uris.append(post.uri) }

        var updated = preferences
        updated.setHiddenPosts(uris)
        await write(updated)
    }

    /// Rules the reader set on their own posts in this session, so the menu can
    /// show what is in force without asking the server again.
    private(set) var replyRules: [String: ThreadGate] = [:]
    private(set) var quotesAllowed: [String: Bool] = [:]

    func gate(for post: PostView) -> ThreadGate { replyRules[post.uri] ?? ThreadGate() }

    func loadGate(for post: PostView) async {
        guard post.author.did == session?.did, replyRules[post.uri] == nil else { return }
        // No record means everybody may answer, which is the default already held.
        if let gate = try? await client.replyRules(forPost: post.uri) {
            replyRules[post.uri] = gate
        }
    }

    func setReplyRule(_ rule: ReplyRule, for post: PostView) async {
        var gate = gate(for: post)
        gate.rules = rule == .everybody ? [.everybody] : [rule]
        await applyGate(gate, to: post)
    }

    func toggleQuotes(for post: PostView) async {
        let allowed = !(quotesAllowed[post.uri] ?? (post.viewer?.embeddingDisabled != true))
        quotesAllowed[post.uri] = allowed
        do { try await client.setQuoteRules(allowed: allowed, forPost: post.uri) }
        catch { quotesAllowed[post.uri] = !allowed }
    }

    /// The author folds a reply away. It stays in the repository — it is hidden
    /// in this thread, not deleted from the network.
    func toggleHiddenReply(_ reply: PostView, inThreadOf root: PostView) async {
        var gate = gate(for: root)
        if let index = gate.hiddenReplies.firstIndex(of: reply.uri) {
            gate.hiddenReplies.remove(at: index)
        } else {
            gate.hiddenReplies.append(reply.uri)
        }
        await applyGate(gate, to: root)
    }

    private func applyGate(_ gate: ThreadGate, to post: PostView) async {
        let previous = replyRules[post.uri]
        replyRules[post.uri] = gate
        do { try await client.setReplyRules(gate, forPost: post.uri) }
        catch { replyRules[post.uri] = previous }
    }

    // MARK: Lists

    private(set) var ownLists: [ListView] = []
    private(set) var subscribedLists: [ListView] = []

    /// Lists the account made, and the ones it has subscribed to for moderation.
    func loadLists() async {
        guard let did = session?.did else { return }

        async let mine = try? client.lists(actor: did)
        async let blocked = try? client.listBlocks()

        if let mine = await mine { ownLists = mine.lists }

        // A muted list comes back as a bare URI, so its name has to be fetched.
        var subscribed: [ListView] = []
        for uri in mutedLists {
            if let loaded = try? await client.list(uri: uri, limit: 1).list {
                subscribed.append(loaded)
            }
        }
        if let blocked = await blocked {
            for list in blocked.lists where !subscribed.contains(where: { $0.uri == list.uri }) {
                subscribed.append(list)
            }
        }
        subscribedLists = subscribed
    }

    func isListMuted(_ uri: String) -> Bool { mutedLists.contains(uri) }

    func toggleListMute(_ list: ListView) async {
        let wasMuted = isListMuted(list.uri)
        if wasMuted { mutedLists.removeAll { $0 == list.uri } } else { mutedLists.append(list.uri) }

        do {
            if wasMuted { try await client.unmuteList(uri: list.uri) }
            else { try await client.muteList(uri: list.uri) }
            await loadModeration()
        } catch {
            if wasMuted { mutedLists.append(list.uri) }
            else { mutedLists.removeAll { $0 == list.uri } }
        }
    }

    /// A list block is a record, so lifting it means deleting that record.
    func toggleListBlock(_ list: ListView) async {
        do {
            if let existing = list.viewer?.blocked {
                try await client.deleteRecord(uri: existing)
            } else {
                try await client.blockList(uri: list.uri)
            }
            await loadLists()
            await loadModeration()
        } catch {
            // The list keeps whatever state the server last confirmed.
        }
    }

    func createList(named name: String) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = try? await client.createList(name: name)
        await loadLists()
    }

    func addToList(_ list: ListView, profile: ActorProfile) async {
        _ = try? await client.addToList(list.uri, did: profile.did)
    }

    // MARK: Feeds

    var savedFeeds: [SavedFeed] { preferences.savedFeedList }

    func isSaved(_ uri: String) -> Bool { savedFeeds.contains { $0.value == uri } }

    /// Keeping a feed writes into the same preferences record as everything else,
    /// so it goes through `write` and carries the rest of it along untouched.
    func toggleSavedFeed(_ uri: String, kind: String = "feed") async {
        var feeds = preferences.savedFeedList
        if let index = feeds.firstIndex(where: { $0.value == uri }) {
            feeds.remove(at: index)
        } else {
            feeds.append(SavedFeed(id: UUID().uuidString.prefix(13).lowercased(),
                                   type: kind, value: uri, pinned: true))
        }
        var updated = preferences
        updated.setSavedFeeds(feeds)
        await write(updated)
    }

    // MARK: Labelers

    func subscribe(to did: String) async {
        guard !preferences.subscribedLabelers.contains(did) else { return }
        var updated = preferences
        updated.setSubscribedLabelers(preferences.subscribedLabelers + [did])
        await write(updated)
        await labelers.setSubscribed(updated.subscribedLabelers, client: client)
    }

    func unsubscribe(from did: String) async {
        var updated = preferences
        updated.setSubscribedLabelers(preferences.subscribedLabelers.filter { $0 != did })
        await write(updated)
        await labelers.setSubscribed(updated.subscribedLabelers, client: client)
    }

    func setVisibility(_ visibility: LabelVisibility, for label: String, from labeler: String) async {
        var updated = preferences
        updated.setVisibility(visibility, for: label, from: labeler)
        await write(updated)
    }

    /// Asks the subscribed labelers about the posts on screen. Only does anything
    /// where the appview did not already answer for them.
    func fillLabels(for posts: [PostView]) async {
        guard !preferences.subscribedLabelers.isEmpty else { return }
        let before = labelers.extraLabels.count
        await labelers.fill(labelsFor: posts.map(\.uri))
        guard labelers.extraLabels.count != before else { return }
        moderationToken += 1
        decisionCache.removeAll()
    }

    func register(moderationOf profile: ActorProfile) {
        if profile.viewer?.muted == true { mutedActors.insert(profile.did) }
        if let blocking = profile.viewer?.blocking { blockedActors[profile.did] = blocking }
    }

    // MARK: Preferences

    func setAdultContent(_ enabled: Bool) async {
        var updated = preferences
        updated.setAdultContent(enabled)
        await write(updated)
    }

    func setVisibility(_ visibility: LabelVisibility, for label: String) async {
        var updated = preferences
        updated.setVisibility(visibility, for: label)
        await write(updated)
    }

    /// Optimistic, then reverted if the server refuses — a moderation setting
    /// that silently fails to save is worse than one that visibly snaps back.
    ///
    /// `putPreferences` replaces the whole array. Writing one that was never read
    /// would therefore delete what other clients put there, so a failed read is a
    /// reason not to write at all rather than a reason to start from nothing.
    private func write(_ updated: Preferences) async {
        if !preferencesAreLoaded {
            await loadModeration()
            guard preferencesAreLoaded else { return }
        }

        let previous = preferences
        preferences = updated
        moderationToken += 1
        decisionCache.removeAll()
        do {
            try await client.putPreferences(updated)
        } catch {
            preferences = previous
            moderationToken += 1
            decisionCache.removeAll()
        }
    }

    // MARK: Decisions

    private var decisionCache: [String: ModerationDecision] = [:]

    var moderationContext: ModerationContext {
        var definitions: [LabelKey: LabelDefinition] = [:]
        for (did, service) in labelers.services {
            for published in service.definitions {
                definitions[LabelKey(labeler: did, value: published.identifier)] = published.asDefinition
            }
        }
        return ModerationContext(preferences: preferences,
                                 mutedActors: mutedActors,
                                 blockedActors: Set(blockedActors.keys),
                                 definitions: definitions,
                                 following: Set(followStates.compactMap { $0.value == nil ? nil : $0.key }),
                                 hiddenPosts: hiddenPosts,
                                 viewerDID: session?.did)
    }

    /// The decision falls for every post in every feed, so it is worked out once
    /// and kept until a setting moves.
    func decision(for post: PostView) -> ModerationDecision {
        // Nothing the reader wrote themselves is ever moderated away from them.
        guard post.author.did != session?.did else { return .allow }
        if let cached = decisionCache[post.uri] { return cached }

        let decision = Moderation.decide(post: post,
                                         extraLabels: labelers.labels(for: post.uri),
                                         context: moderationContext)
        decisionCache[post.uri] = decision
        return decision
    }

    func decision(for profile: ActorProfile) -> ModerationDecision {
        guard profile.did != session?.did else { return .allow }
        return Moderation.decide(profile: profile, context: moderationContext)
    }

    /// What the reader sees after choosing to uncover something.
    func effectiveDecision(for post: PostView) -> ModerationDecision {
        var decision = self.decision(for: post)
        if revealed.contains(post.uri), decision.verdict.isRevealable {
            decision.verdict = .badge
        }
        return decision
    }

    func toggleReveal(_ uri: String) {
        if revealed.contains(uri) { revealed.remove(uri) } else { revealed.insert(uri) }
    }

    func isMuted(_ did: String) -> Bool { mutedActors.contains(did) }
    func isBlocked(_ did: String) -> Bool { blockedActors[did] != nil }

    /// Hidden posts stay out of every feed the app draws.
    func isHidden(_ did: String) -> Bool { isMuted(did) || isBlocked(did) }

    func toggleMute(_ profile: ActorProfile) async {
        let wasMuted = isMuted(profile.did)
        if wasMuted { mutedActors.remove(profile.did) } else { mutedActors.insert(profile.did) }

        do {
            if wasMuted {
                try await client.unmute(did: profile.did)
            } else {
                try await client.mute(did: profile.did)
            }
        } catch {
            if wasMuted { mutedActors.insert(profile.did) } else { mutedActors.remove(profile.did) }
        }
    }

    func toggleBlock(_ profile: ActorProfile) async {
        if let existing = blockedActors[profile.did] {
            blockedActors[profile.did] = nil
            do { try await client.deleteRecord(uri: existing) }
            catch { blockedActors[profile.did] = existing }
        } else {
            blockedActors[profile.did] = "pending"
            do {
                let response = try await client.block(did: profile.did)
                blockedActors[profile.did] = response.uri
                // Blocking implies unfollowing on this side of the relationship.
                followStates[profile.did] = String?.none
            } catch {
                blockedActors[profile.did] = nil
            }
        }
    }

    func report(_ subject: ReportSubject, reason: ModerationReason, note: String?,
                labeler: String? = nil) async throws {
        try await client.report(subject: subject, reason: reason, note: note, labeler: labeler)
    }

    // MARK: Who may write

    /// An account with no declaration takes messages from anyone, so that is the
    /// state until the record says otherwise.
    private(set) var messageRule: MessageRule = .all

    func loadMessageRule() async {
        guard session != nil else { return }
        if let rule = try? await client.messageRule() { messageRule = rule }
    }

    func setMessageRule(_ rule: MessageRule) async {
        let previous = messageRule
        messageRule = rule
        do { try await client.setMessageRule(rule) }
        catch { messageRule = previous }
    }

    // MARK: - What reaches you

    private(set) var notificationPreferences = NotificationPreferences.defaults
    /// Same discipline as the preferences record: never write a set that was
    /// never successfully read, or the defaults would overwrite whatever another
    /// client had chosen.
    private(set) var notificationPreferencesAreLoaded = false

    func loadNotificationPreferences() async {
        guard let loaded = try? await client.notificationPreferences() else { return }
        notificationPreferences = loaded
        notificationPreferencesAreLoaded = true
    }

    /// Carries the device's four retired switches up to the account, once.
    ///
    /// Only `push`, never `list`. Those booleans only ever silenced local
    /// banners; writing them into `list` would hide things from the
    /// notifications tab that were never hidden — and would do it on every other
    /// client the account uses. That is the most dangerous line in this change.
    func migrateNotificationChoices(from settings: AppSettings) async {
        guard !settings.notificationsMigrated else { return }
        guard notificationPreferencesAreLoaded else { return }   // never guess

        defer {
            settings.notificationsMigrated = true
            settings.forgetRetiredNotificationChoices()
        }
        guard let chosen = settings.retiredNotificationChoices() else { return }

        var updated = notificationPreferences
        if let value = chosen["like"] { updated[.like].push = value }
        if let value = chosen["repost"] { updated[.repost].push = value }
        if let value = chosen["follow"] { updated[.follow].push = value }
        // One switch used to cover all three of these.
        if let value = chosen["reply"] {
            updated[.reply].push = value
            updated[.mention].push = value
            updated[.quote].push = value
        }
        await setNotificationPreferences(updated)
    }

    /// Optimistic, and puts the previous set back if the server refuses.
    func setNotificationPreferences(_ preferences: NotificationPreferences) async {
        guard notificationPreferencesAreLoaded else { return }
        let previous = notificationPreferences
        notificationPreferences = preferences
        do {
            // The server echoes what it stored; take that rather than the guess.
            notificationPreferences = try await client.setNotificationPreferences(preferences)
        } catch {
            notificationPreferences = previous
        }
    }

    /// Removes one of the user's own posts. Feeds drop it through `deletedPosts`,
    /// so the row disappears without reloading the whole timeline.
    func deletePost(_ post: PostView) async {
        guard post.author.did == session?.did else { return }
        deletedPosts.insert(post.uri)
        do {
            try await client.deleteRecord(uri: post.uri)
        } catch {
            deletedPosts.remove(post.uri)
        }
    }

    func noteReplyAdded(to uri: String) {
        postStates[uri]?.replyCount += 1
    }

    /// A quote leaves no mark on the quoted post's viewer state, so the count is
    /// moved here the moment the quote is written.
    func noteQuoteAdded(to uri: String) {
        if postStates[uri] == nil { return }
        postStates[uri]?.quoteCount += 1
    }

    // MARK: - Keychain

    private func store(session: ATSession, service: String) {
        let stored = StoredSession(session: session, service: service, dpopKey: nil)
        accounts.removeAll { $0.session.did == session.did }
        accounts.append(stored)
        AccountsStore.save(StoredAccounts(accounts: accounts, activeDID: session.did))
    }
}
