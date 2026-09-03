//
//  OwnSpace.swift
//  Relays
//
//  Moderation pointed inward: who may answer a post, who may quote it, and which
//  replies its author has folded away. These are records in the author's own
//  repository, so they hold for every client — the rules travel with the post,
//  not with the app that wrote them.
//
//  Both records live at the same rkey as the post they belong to, which is what
//  makes them findable without an index.
//

import Foundation

/// Who may reply. Absent means everybody; an empty allow list means nobody.
enum ReplyRule: Hashable, Identifiable {
    case everybody
    case nobody
    case mentioned
    case followed
    case followers
    case list(uri: String)

    var id: String {
        switch self {
        case .everybody: return "everybody"
        case .nobody: return "nobody"
        case .mentioned: return "mentioned"
        case .followed: return "followed"
        case .followers: return "followers"
        case .list(let uri): return "list:\(uri)"
        }
    }

    /// The choices offered when writing a post. A list rule is set from a list.
    static let offered: [ReplyRule] = [.everybody, .followed, .mentioned, .followers, .nobody]

    var label: String {
        switch self {
        case .everybody: return L(.replyEverybody)
        case .nobody: return L(.replyNobody)
        case .mentioned: return L(.replyMentioned)
        case .followed: return L(.replyFollowed)
        case .followers: return L(.replyFollowers)
        case .list: return L(.replyList)
        }
    }

    /// The rule as the protocol writes it. `everybody` has none: the record is
    /// simply not written.
    var encoded: JSONValue? {
        switch self {
        case .everybody, .nobody: return nil
        case .mentioned: return .object(["$type": .string("app.bsky.feed.threadgate#mentionRule")])
        case .followed: return .object(["$type": .string("app.bsky.feed.threadgate#followingRule")])
        case .followers: return .object(["$type": .string("app.bsky.feed.threadgate#followerRule")])
        case .list(let uri):
            return .object(["$type": .string("app.bsky.feed.threadgate#listRule"),
                            "list": .string(uri)])
        }
    }

    init?(decoded: JSONValue) {
        guard let type = decoded.type else { return nil }
        switch type {
        case "app.bsky.feed.threadgate#mentionRule": self = .mentioned
        case "app.bsky.feed.threadgate#followingRule": self = .followed
        case "app.bsky.feed.threadgate#followerRule": self = .followers
        case "app.bsky.feed.threadgate#listRule":
            guard let uri = decoded.objectValue?["list"]?.stringValue else { return nil }
            self = .list(uri: uri)
        default: return nil
        }
    }
}

/// What a post's own rules say, as the app holds them.
struct ThreadGate: Equatable {
    var rules: [ReplyRule] = [.everybody]
    var hiddenReplies: [String] = []

    var allowsEverybody: Bool { rules == [.everybody] }
    var allowsNobody: Bool { rules.isEmpty || rules == [.nobody] }

    /// One line for the post: what the reader needs to know without opening it.
    var summary: String? {
        if allowsEverybody { return nil }
        if allowsNobody { return L(.replyNobodyNotice) }
        return L(.replyLimitedNotice, rules.map(\.label).joined(separator: ", "))
    }
}

// MARK: - Posts hidden for oneself

extension Preferences {

    static let hiddenPosts = "app.bsky.actor.defs#hiddenPostsPref"

    var hiddenPostURIs: [String] {
        guard let entry = entries.first(where: { $0.type == Self.hiddenPosts })?.objectValue,
              case .array(let items)? = entry["items"] else { return [] }
        return items.compactMap(\.stringValue)
    }

    mutating func setHiddenPosts(_ uris: [String]) {
        replaceEntry(type: Self.hiddenPosts, with: .object([
            "$type": .string(Self.hiddenPosts),
            "items": .array(uris.map { .string($0) }),
        ]))
    }
}
