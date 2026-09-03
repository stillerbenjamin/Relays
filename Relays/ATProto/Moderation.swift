//
//  Moderation.swift
//  Relays
//
//  One decision per thing on screen. Everything known about a post — the labels
//  on it, the labels on its author, what the account has muted or blocked, what
//  the user asked for per label, and the rules that never leave this device —
//  goes in, and a single verdict comes out, with the reason it was reached.
//
//  Two rules hold the whole thing together: the strictest verdict wins, and the
//  device can only ever be stricter than the network. Without them the result
//  would depend on the order labels happen to arrive in.
//

import Foundation

/// What to do with a thing, from mildest to strictest.
enum ModerationVerdict: Int, Comparable, Equatable {
    case allow = 0
    /// A chip on the post — what the app does with every label today.
    case badge
    /// A line above the post; the content stays readable.
    case warn
    /// The pictures are covered, the text is not.
    case blurMedia
    /// The whole post is covered behind its reason.
    case blurContent
    /// Never rendered at all.
    case hide

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Whether the reader can take one step past the verdict.
    var isRevealable: Bool { self == .blurMedia || self == .blurContent }
}

/// Which layer decided, so the interface can say so.
enum ModerationSource: Equatable {
    /// A label, and who applied it.
    case labeler(did: String, label: String)
    /// The author labelled their own post.
    case selfLabel(String)
    /// A block, a mute, or being blocked.
    case account
    /// A rule that only exists on this device.
    case device
    /// A word the reader muted. Stored with the account, so it holds everywhere.
    case mutedWord(String)
    /// This one post, put away by the reader.
    case hiddenPost
}

struct ModerationDecision: Equatable {
    var verdict: ModerationVerdict = .allow
    /// Ready to show: the label's name, or why the account is hidden.
    var reason: String?
    var source: ModerationSource?
    /// Every label found, so the chips can still be drawn under a warning.
    var labels: [String] = []

    static let allow = ModerationDecision()

    var hides: Bool { verdict == .hide }
    var blursMedia: Bool { verdict == .blurMedia || verdict == .blurContent }
    var blursContent: Bool { verdict == .blurContent }
    var warns: Bool { verdict == .warn }

    /// The strictest of the two, keeping the reason that belongs to it.
    func strictest(_ other: ModerationDecision) -> ModerationDecision {
        var winner = other.verdict > verdict ? other : self
        winner.labels = Array(Set(labels + other.labels)).sorted()
        return winner
    }
}

// MARK: - What a label means

/// The shape every labeler publishes for its own values. Relays carries the
/// global ones itself; the rest arrive from the labeler once services can be
/// subscribed to, and unknown values stay a chip until then.
struct LabelDefinition {
    let identifier: String
    var blurs: Blur = .none
    var severity: Severity = .inform
    var defaultSetting: LabelVisibility = .warn
    var adultOnly: Bool = false
    /// A value the user cannot switch off.
    var configurable: Bool = true
    /// The name a labeler published for this value, where one exists.
    var name: String = ""

    enum Blur { case none, media, content }
    enum Severity { case none, inform, alert }

    /// What to call it: the labeler's own wording, the app's for the values the
    /// protocol itself defines, and the bare value when nobody said anything.
    var title: String {
        if !name.isEmpty { return name }
        switch identifier {
        case "!hide": return L(.labelHidden)
        case "!warn": return L(.labelWarned)
        case "porn": return L(.labelPorn)
        case "sexual": return L(.labelSexual)
        case "nudity": return L(.labelNudity)
        case "graphic-media": return L(.labelGraphic)
        default: return identifier
        }
    }
}

enum LabelCatalog {

    /// The values defined by the protocol rather than by any one service. Their
    /// behaviour is fixed: `!hide` cannot be switched off, and the adult ones
    /// answer to the adult-content setting before anything else.
    static let global: [String: LabelDefinition] = [
        "!hide": LabelDefinition(identifier: "!hide", blurs: .content, severity: .alert,
                                 defaultSetting: .hide, configurable: false),
        "!warn": LabelDefinition(identifier: "!warn", blurs: .content, severity: .alert,
                                 defaultSetting: .warn, configurable: false),
        "porn": LabelDefinition(identifier: "porn", blurs: .media, severity: .none,
                                defaultSetting: .hide, adultOnly: true),
        "sexual": LabelDefinition(identifier: "sexual", blurs: .media, severity: .none,
                                  defaultSetting: .warn, adultOnly: true),
        "graphic-media": LabelDefinition(identifier: "graphic-media", blurs: .media,
                                         severity: .none, defaultSetting: .warn, adultOnly: true),
        "nudity": LabelDefinition(identifier: "nudity", blurs: .media, severity: .none,
                                  defaultSetting: .warn),
    ]

    /// Values the user can set, in the order the settings screen shows them.
    static let adjustable: [String] = ["porn", "sexual", "graphic-media", "nudity"]

    static func definition(for value: String) -> LabelDefinition? { global[value] }

    /// A label nobody has published a definition for. It says something, so it
    /// is shown — but it does not act.
    static func fallback(for value: String) -> LabelDefinition {
        LabelDefinition(identifier: value, blurs: .none, severity: .inform, defaultSetting: .ignore)
    }
}

// MARK: - The decision

struct ModerationContext {
    var preferences: Preferences = Preferences()
    var mutedActors: Set<String> = []
    var blockedActors: Set<String> = []
    /// What a subscribed labeler says its own values mean. Values the protocol
    /// itself defines are not in here — nobody redefines `!hide`.
    var definitions: [LabelKey: LabelDefinition] = [:]
    /// Accounts the reader follows, for the words that spare them.
    var following: Set<String> = []
    /// Single posts the reader put away, kept with the account.
    var hiddenPosts: Set<String> = []
    /// Labels that never leave this device: the reader's own account.
    var viewerDID: String?

    /// `!no-unauthenticated` only means anything to a reader who is not signed
    /// in, which this app never is once it renders a feed.
    var isSignedIn: Bool { viewerDID != nil }
}

enum Moderation {

    /// A post, everything about it, and what to do.
    static func decide(post: PostView, extraLabels: [ContentLabel] = [],
                       context: ModerationContext) -> ModerationDecision {
        var decision = account(for: post.author, context: context)

        // Labels from the appview and labels fetched from a labeler directly are
        // the same thing; the same one arriving twice must not count twice.
        var seen = Set<String>()
        let labels = ((post.labels ?? []) + extraLabels).filter { label in
            seen.insert(label.id).inserted && !label.isNegated
        }

        for label in labels {
            decision = decision.strictest(verdict(for: label, author: post.author.did,
                                                  context: context))
        }
        decision = decision.strictest(mutedWord(in: post, context: context))

        // A post the reader put away themselves needs no further reasoning.
        if context.hiddenPosts.contains(post.uri) {
            decision = decision.strictest(
                ModerationDecision(verdict: .hide, reason: L(.hiddenPostNotice),
                                   source: .hiddenPost))
        }
        for label in post.author.labels ?? [] where label.val != "!no-unauthenticated" {
            decision = decision.strictest(verdict(for: label, author: post.author.did,
                                                  context: context))
        }
        return decision
    }

    /// A profile on its own — the header of a profile screen, an author in a list.
    static func decide(profile: ActorProfile, context: ModerationContext) -> ModerationDecision {
        var decision = account(for: profile, context: context)
        for label in profile.labels ?? [] where label.val != "!no-unauthenticated" {
            decision = decision.strictest(verdict(for: label, author: profile.did,
                                                  context: context))
        }
        return decision
    }

    // MARK: Pieces

    /// Blocks and mutes, which outrank every label.
    private static func account(for profile: ActorProfile,
                                context: ModerationContext) -> ModerationDecision {
        let viewer = profile.viewer

        if viewer?.blocking != nil || context.blockedActors.contains(profile.did) {
            return ModerationDecision(verdict: .hide, reason: L(.moderationBlocked), source: .account)
        }
        if viewer?.blockedBy == true {
            return ModerationDecision(verdict: .hide, reason: L(.moderationBlockedBy), source: .account)
        }
        if let list = viewer?.blockingByList {
            return ModerationDecision(verdict: .hide,
                                      reason: L(.moderationViaList, list.name ?? ""), source: .account)
        }
        if let list = viewer?.mutedByList {
            return ModerationDecision(verdict: .hide,
                                      reason: L(.moderationViaList, list.name ?? ""), source: .account)
        }
        if viewer?.muted == true || context.mutedActors.contains(profile.did) {
            return ModerationDecision(verdict: .hide, reason: L(.moderationMuted), source: .account)
        }
        return .allow
    }

    /// A word the reader muted, in the text or in a hashtag.
    private static func mutedWord(in post: PostView,
                                  context: ModerationContext) -> ModerationDecision {
        let words = context.preferences.mutedWordList
        guard !words.isEmpty else { return .allow }

        let tags = post.record.facets?.flatMap { facet in
            facet.features.compactMap { feature -> String? in
                if case .tag(let value) = feature { return value }
                return nil
            }
        } ?? []
        let isFollowed = context.following.contains(post.author.did)

        for word in words where word.matches(text: post.record.text, tags: tags,
                                             isFollowed: isFollowed) {
            return ModerationDecision(verdict: .hide, reason: L(.mutedWordReason, word.value),
                                      source: .mutedWord(word.value))
        }
        return .allow
    }

    /// One label, run through its definition and the reader's setting.
    private static func verdict(for label: ContentLabel, author: String,
                                context: ModerationContext) -> ModerationDecision {
        let published = context.definitions[LabelKey(labeler: label.src, value: label.val)]
        let known = LabelCatalog.definition(for: label.val) ?? published
        let definition = known ?? LabelCatalog.fallback(for: label.val)
        let isSelfLabel = label.src == author
        let source: ModerationSource = isSelfLabel
            ? .selfLabel(label.val)
            : .labeler(did: label.src, label: label.val)

        // Adult content answers to one switch before any per-label setting. With
        // it off, an adult label hides the post whatever else was chosen.
        if definition.adultOnly, !context.preferences.adultContentEnabled {
            return ModerationDecision(verdict: .hide, reason: definition.title,
                                      source: source, labels: [label.val])
        }

        let chosen = definition.configurable
            ? context.preferences.visibility(for: label.val, from: isSelfLabel ? nil : label.src)
                ?? definition.defaultSetting
            : definition.defaultSetting

        var decision = ModerationDecision(verdict: .allow, reason: definition.title,
                                          source: source, labels: [label.val])

        switch chosen {
        case .hide:
            decision.verdict = .hide
        case .warn:
            switch definition.blurs {
            case .content: decision.verdict = .blurContent
            case .media: decision.verdict = .blurMedia
            case .none: decision.verdict = definition.severity == .alert ? .warn : .badge
            }
        case .ignore:
            // Even ignored, a label that says something still says it.
            decision.verdict = definition.severity == .none ? .allow : .badge
        }
        return decision
    }
}
