//
//  Preferences.swift
//  Relays
//
//  The account's preferences are one array shared by every client that ever
//  signed in. `putPreferences` replaces the whole thing, so an entry this app
//  does not understand — saved feeds, muted words, a birth date — has to be
//  carried through untouched. Dropping one deletes another client's settings.
//

import Foundation

/// Just enough JSON to hold an entry Relays does not model.
indirect enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // A whole number has to go back out as one. Lexicon validation on the
            // server rejects 1.0 where it expects an integer.
            if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
    var type: String? { objectValue?["$type"]?.stringValue }
}

/// What the user chose to happen when a label appears.
enum LabelVisibility: String, Codable, CaseIterable, Identifiable {
    case ignore, warn, hide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ignore: return L(.labelIgnore)
        case .warn: return L(.labelWarn)
        case .hide: return L(.labelHide)
        }
    }

    /// The protocol still writes "show" where newer clients write "ignore".
    init(stored: String) {
        switch stored {
        case "hide": self = .hide
        case "warn": self = .warn
        default: self = .ignore
        }
    }
}

/// The preference array, with the two entries Relays manages read out of it and
/// everything else kept verbatim.
struct Preferences: Equatable {

    private(set) var entries: [JSONValue]

    static let personalDetails = "app.bsky.actor.defs#personalDetailsPref"
    static let adultContent = "app.bsky.actor.defs#adultContentPref"
    static let contentLabel = "app.bsky.actor.defs#contentLabelPref"
    static let labelers = "app.bsky.actor.defs#labelersPref"
    static let savedFeeds = "app.bsky.actor.defs#savedFeedsPrefV2"

    init(entries: [JSONValue] = []) {
        self.entries = entries
    }

    // MARK: - Reading

    /// Off unless the account says otherwise. Nothing about an empty preference
    /// array should be read as consent.
    var adultContentEnabled: Bool {
        entry(ofType: Self.adultContent)?["enabled"]?.boolValue ?? false
    }

    /// Keyed the way a label arrives: the labeler's DID and the label value, and
    /// an empty DID for the settings that apply to every source.
    var labelVisibility: [LabelKey: LabelVisibility] {
        var result: [LabelKey: LabelVisibility] = [:]
        for entry in entries where entry.type == Self.contentLabel {
            guard let object = entry.objectValue,
                  let label = object["label"]?.stringValue,
                  let visibility = object["visibility"]?.stringValue else { continue }
            let key = LabelKey(labeler: object["labelerDid"]?.stringValue, value: label)
            result[key] = LabelVisibility(stored: visibility)
        }
        return result
    }

    /// The feeds the account keeps, in the order they are shown.
    var savedFeedList: [SavedFeed] {
        guard let entry = entries.first(where: { $0.type == Self.savedFeeds })?.objectValue,
              case .array(let items)? = entry["items"] else { return [] }
        return items.compactMap { item -> SavedFeed? in
            guard let object = item.objectValue,
                  let id = object["id"]?.stringValue,
                  let type = object["type"]?.stringValue,
                  let value = object["value"]?.stringValue else { return nil }
            return SavedFeed(id: id, type: type, value: value,
                             pinned: object["pinned"]?.boolValue ?? false)
        }
    }

    mutating func setSavedFeeds(_ feeds: [SavedFeed]) {
        replaceEntry(type: Self.savedFeeds, with: .object([
            "$type": .string(Self.savedFeeds),
            "items": .array(feeds.map { feed in
                .object(["id": .string(feed.id),
                         "type": .string(feed.type),
                         "value": .string(feed.value),
                         "pinned": .bool(feed.pinned)])
            }),
        ]))
    }

    /// The moderation services the account subscribes to, in their stored order.
    var subscribedLabelers: [String] {
        guard let entry = entry(ofType: Self.labelers),
              case .array(let items)? = entry["labelers"] else { return [] }
        return items.compactMap { $0.objectValue?["did"]?.stringValue }
    }

    mutating func setSubscribedLabelers(_ dids: [String]) {
        replaceEntry(type: Self.labelers, with: .object([
            "$type": .string(Self.labelers),
            "labelers": .array(dids.map { .object(["did": .string($0)]) }),
        ]))
    }

    func visibility(for value: String, from labeler: String?) -> LabelVisibility? {
        let settings = labelVisibility
        if let labeler, let specific = settings[LabelKey(labeler: labeler, value: value)] {
            return specific
        }
        return settings[LabelKey(labeler: nil, value: value)]
    }

    // MARK: - Writing

    /// The birth date the account was made with. Nothing reads it yet; it is
    /// written because the network expects the client that creates an account to
    /// record it, and because the adult-content setting rests on it.
    mutating func setBirthDate(_ date: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        replaceEntry(type: Self.personalDetails, with: .object([
            "$type": .string(Self.personalDetails),
            "birthDate": .string(formatter.string(from: date)),
        ]))
    }

    mutating func setAdultContent(_ enabled: Bool) {
        replaceEntry(type: Self.adultContent, with: .object([
            "$type": .string(Self.adultContent),
            "enabled": .bool(enabled),
        ]))
    }

    /// One entry per label and source. `nil` removes the setting so the label
    /// falls back to what its definition asks for.
    mutating func setVisibility(_ visibility: LabelVisibility?, for value: String,
                                from labeler: String? = nil) {
        entries.removeAll { entry in
            guard entry.type == Self.contentLabel, let object = entry.objectValue else { return false }
            return object["label"]?.stringValue == value
                && object["labelerDid"]?.stringValue == labeler
        }
        guard let visibility else { return }

        var object: [String: JSONValue] = [
            "$type": .string(Self.contentLabel),
            "label": .string(value),
            "visibility": .string(visibility.rawValue),
        ]
        if let labeler { object["labelerDid"] = .string(labeler) }
        entries.append(.object(object))
    }

    // MARK: - Plumbing

    private func entry(ofType type: String) -> [String: JSONValue]? {
        entries.first { $0.type == type }?.objectValue
    }

    mutating func replaceEntry(type: String, with value: JSONValue) {
        if let index = entries.firstIndex(where: { $0.type == type }) {
            entries[index] = value
        } else {
            entries.append(value)
        }
    }
}

/// A label setting is per value, and optionally per labeler.
struct LabelKey: Hashable {
    let labeler: String?
    let value: String
}
