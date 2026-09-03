//
//  NotificationPreferences.swift
//  Relays
//
//  What reaches you, kept on the account rather than on this device. The app
//  had four booleans in its own UserDefaults, so a phone and a Mac signed in to
//  the same account disagreed, and no other client knew about either.
//
//  Two traps live in this file, both from the lexicon:
//
//  1. The twelve kinds are not one shape. Eight carry an audience as well as
//     their two switches; four carry only the switches. Sending an `include` on
//     one of the four, or leaving it off one of the eight, is a validation
//     failure — so encoding has to know which is which.
//  2. The kinds and the notification reasons are two overlapping sets, not one.
//     `contact-match` is a reason with no preference; `chat` is a preference
//     with no reason. Modelling them as one type produces a setting for
//     something that never arrives, or an arrival with no setting.
//

import Foundation

struct NotificationPreferences: Codable, Hashable, Sendable {

    /// The twelve this app reads and writes, by their wire names.
    ///
    /// `chat` is deliberately absent: the lexicon marks it deprecated and says
    /// the server returns only a default value for it. Showing it would show a
    /// lie. Message settings come from `chat.bsky.notification` instead.
    enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        case reply, mention, quote
        case like, repost, likeViaRepost, repostViaRepost
        case follow
        case verified, unverified, starterpackJoined
        case subscribedPost

        var id: String { rawValue }

        /// Whether this kind can be narrowed to people you follow.
        /// `app.bsky.notification.defs#filterablePreference` versus `#preference`.
        var isFilterable: Bool {
            switch self {
            case .reply, .mention, .quote, .like, .repost,
                 .likeViaRepost, .repostViaRepost, .follow:
                return true
            case .verified, .unverified, .starterpackJoined, .subscribedPost:
                return false
            }
        }

        /// The notification this preference governs. `contact-match` has none
        /// here, which is why this is an optional in the other direction too.
        var reason: ATNotification.Reason {
            switch self {
            case .reply: return .reply
            case .mention: return .mention
            case .quote: return .quote
            case .like: return .like
            case .repost: return .repost
            case .likeViaRepost: return .likeViaRepost
            case .repostViaRepost: return .repostViaRepost
            case .follow: return .follow
            case .verified: return .verified
            case .unverified: return .unverified
            case .starterpackJoined: return .starterpackJoined
            case .subscribedPost: return .subscribedPost
            }
        }

        /// The one place the reason-to-kind direction is written down.
        /// `contact-match` has no preference of its own.
        static func governing(_ reason: ATNotification.Reason) -> Kind? {
            allCases.first { $0.reason == reason }
        }
    }

    enum Audience: String, Codable, Sendable, CaseIterable, Identifiable {
        case all, follows

        var id: String { rawValue }
        var label: String { self == .all ? L(.notifyAudienceAll) : L(.notifyAudienceFollows) }
    }

    struct Setting: Codable, Hashable, Sendable {
        /// Present exactly when the kind is filterable.
        var include: Audience?
        /// Whether it appears in the notifications list at all.
        var list: Bool
        /// Whether it is worth interrupting somebody for.
        var push: Bool

        static let on = Setting(include: .all, list: true, push: true)
    }

    var settings: [Kind: Setting] = [:]

    /// Everything on, which is what a server answers for an account that has
    /// never been asked.
    static var defaults: NotificationPreferences {
        var prefs = NotificationPreferences()
        for kind in Kind.allCases {
            prefs.settings[kind] = Setting(include: kind.isFilterable ? .all : nil,
                                           list: true, push: true)
        }
        return prefs
    }

    subscript(kind: Kind) -> Setting {
        get { settings[kind] ?? Setting(include: kind.isFilterable ? .all : nil,
                                        list: true, push: true) }
        set { settings[kind] = newValue }
    }

    /// The audience shared by the eight filterable kinds, or nil when they do
    /// not agree — another client can set them one at a time.
    var sharedAudience: Audience? {
        let audiences = Set(Kind.allCases.filter(\.isFilterable).map { self[$0].include ?? .all })
        return audiences.count == 1 ? audiences.first : nil
    }

    mutating func setAudience(_ audience: Audience) {
        for kind in Kind.allCases where kind.isFilterable {
            settings[kind, default: Setting(include: .all, list: true, push: true)]
                .include = audience
        }
    }

    // MARK: - The wire

    private struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ kind: Kind) { stringValue = kind.rawValue }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for kind in Kind.allCases {
            guard let key = CodingKeys(stringValue: kind.rawValue),
                  let setting = try? c.decode(Setting.self, forKey: key) else { continue }
            // A server that sends an audience for a kind that has none, or
            // omits one for a kind that needs it, does not get to corrupt the
            // shape this app sends back.
            settings[kind] = Setting(include: kind.isFilterable ? (setting.include ?? .all) : nil,
                                     list: setting.list, push: setting.push)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for kind in Kind.allCases {
            let setting = self[kind]
            try c.encode(Setting(include: kind.isFilterable ? (setting.include ?? .all) : nil,
                                 list: setting.list, push: setting.push),
                         forKey: CodingKeys(kind))
        }
    }
}

/// The delivery rule, which used to live on `AppSettings` as four booleans —
/// one of which covered replies, mentions and quotes together.
extension NotificationPreferences: NotificationKinds {
    func wantsNotification(ofKind reason: String) -> Bool {
        guard let known = ATNotification.Reason(rawValue: reason) else {
            // Something the protocol added since. There is no preference to
            // consult, and swallowing it silently is worse than one banner.
            return true
        }
        guard let kind = Kind.governing(known) else {
            // `contact-match` has no preference of its own.
            return true
        }
        return self[kind].push
    }
}
