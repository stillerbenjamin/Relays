//
//  MutedWords.swift
//  Relays
//
//  Words the account never wants to read, kept in its preferences so they hold
//  in every client. Relays already had rules that do more — a regular expression
//  is beyond what the protocol can store — but those never leave the device.
//  These two layers sit next to each other on purpose.
//

import Foundation

struct MutedWord: Identifiable, Hashable {

    /// Where a word counts.
    enum Target: String, CaseIterable, Identifiable {
        /// The text of the post.
        case content
        /// Its hashtags only.
        case tag

        var id: String { rawValue }

        var label: String {
            switch self {
            case .content: return L(.mutedWordText)
            case .tag: return L(.mutedWordTag)
            }
        }
    }

    /// Whose posts it applies to.
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case excludeFollowing = "exclude-following"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return L(.mutedWordEveryone)
            case .excludeFollowing: return L(.mutedWordStrangers)
            }
        }
    }

    var id: String
    var value: String
    var targets: [Target] = [.content, .tag]
    var scope: Scope = .all
    var expiresAt: Date?

    init(id: String = UUID().uuidString.lowercased(), value: String,
         targets: [Target] = [.content, .tag], scope: Scope = .all, expiresAt: Date? = nil) {
        self.id = id
        self.value = value
        self.targets = targets
        self.scope = scope
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Words are matched on whole words, not on pieces of them: muting "art"
    /// must not take "start" with it. A value of several words matches as a
    /// sequence, in order.
    func matches(text: String, tags: [String], isFollowed: Bool) -> Bool {
        guard !isExpired else { return false }
        if scope == .excludeFollowing, isFollowed { return false }

        let needle = Self.tokens(in: value)
        guard !needle.isEmpty else { return false }

        if targets.contains(.tag), Self.contains(needle, inAnyOf: tags) { return true }
        if targets.contains(.content), Self.contains(needle, in: text) { return true }
        return false
    }

    // MARK: - Matching

    /// Lowercased words, with punctuation dropped. Diacritics are kept: folding
    /// them would quietly make "gross" match "groß", which is not what anybody
    /// typed.
    static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func contains(_ needle: [String], in text: String) -> Bool {
        let haystack = tokens(in: text)
        guard needle.count <= haystack.count else { return false }
        if needle.count == 1 { return haystack.contains(needle[0]) }

        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }

    private static func contains(_ needle: [String], inAnyOf tags: [String]) -> Bool {
        tags.contains { contains(needle, in: $0) }
    }
}

// MARK: - Storage

extension Preferences {

    static let mutedWords = "app.bsky.actor.defs#mutedWordsPref"

    var mutedWordList: [MutedWord] {
        guard let entry = entries.first(where: { $0.type == Self.mutedWords })?.objectValue,
              case .array(let items)? = entry["items"] else { return [] }

        return items.compactMap { item -> MutedWord? in
            guard let object = item.objectValue,
                  let value = object["value"]?.stringValue, !value.isEmpty else { return nil }

            let targets: [MutedWord.Target]
            if case .array(let stored)? = object["targets"] {
                targets = stored.compactMap { $0.stringValue }
                    .compactMap(MutedWord.Target.init(rawValue:))
            } else {
                targets = [.content, .tag]
            }

            return MutedWord(
                id: object["id"]?.stringValue ?? value,
                value: value,
                targets: targets.isEmpty ? [.content, .tag] : targets,
                scope: object["actorTarget"]?.stringValue
                    .flatMap(MutedWord.Scope.init(rawValue:)) ?? .all,
                expiresAt: object["expiresAt"]?.stringValue.flatMap(Self.date(from:)))
        }
    }

    mutating func setMutedWords(_ words: [MutedWord]) {
        let items: [JSONValue] = words.map { word in
            var object: [String: JSONValue] = [
                "id": .string(word.id),
                "value": .string(word.value),
                "targets": .array(word.targets.map { .string($0.rawValue) }),
                "actorTarget": .string(word.scope.rawValue),
            ]
            if let expiresAt = word.expiresAt {
                object["expiresAt"] = .string(Self.timestamp(from: expiresAt))
            }
            return .object(object)
        }
        replaceEntry(type: Self.mutedWords, with: .object([
            "$type": .string(Self.mutedWords),
            "items": .array(items),
        ]))
    }

    private static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    private static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
