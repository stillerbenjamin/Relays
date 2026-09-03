//
//  FeedRules.swift
//  Relays
//
//  Filters that run on the device and are reported to nobody. Keywords, regular
//  expressions and structural conditions, each with an optional expiry.
//

import Foundation
import Observation

struct FeedRule: Codable, Identifiable, Hashable {

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case keyword        // plain text, case insensitive
        case regex          // NSRegularExpression against the post text
        case domain         // link previews pointing at this host
        case handle         // author handle contains
        case selfHostedOnly // structural: keep only accounts off Bluesky's own PDS

        var id: String { rawValue }

        var label: String {
            switch self {
            case .keyword: return L(.ruleKeyword)
            case .regex: return L(.ruleRegex)
            case .domain: return L(.ruleDomain)
            case .handle: return L(.ruleHandle)
            case .selfHostedOnly: return L(.ruleSelfHosted)
            }
        }

        var needsValue: Bool { self != .selfHostedOnly }
    }

    var id = UUID()
    var kind: Kind
    var value: String
    var isEnabled = true
    /// Muting that ends by itself — the reason keyword filters usually rot.
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    var isActive: Bool { isEnabled && !isExpired }
}

@MainActor
@Observable
final class FeedRules {

    private(set) var rules: [FeedRule] = []

    private let defaults = UserDefaults.standard
    private let key = "settings.feedRules"
    private var compiled: [UUID: NSRegularExpression] = [:]

    init() {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([FeedRule].self, from: data) {
            rules = stored
        }
        recompile()
    }

    var activeCount: Int { rules.filter(\.isActive).count }

    func add(_ rule: FeedRule) {
        rules.append(rule)
        persist()
    }

    func update(_ rule: FeedRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    func remove(_ rule: FeedRule) {
        rules.removeAll { $0.id == rule.id }
        compiled[rule.id] = nil
        persist()
    }

    /// Drops rules whose expiry has passed. Called when the rule screen opens.
    func pruneExpired() {
        let before = rules.count
        rules.removeAll { $0.isExpired }
        if rules.count != before { persist() }
    }

    /// True when the post survives every active rule.
    func allows(_ item: FeedViewPost, origin: AccountOrigin?) -> Bool {
        let post = item.post
        let text = post.record.text

        for rule in rules where rule.isActive {
            switch rule.kind {
            case .keyword:
                if text.localizedCaseInsensitiveContains(rule.value) { return false }

            case .regex:
                guard let expression = compiled[rule.id] else { continue }
                let range = NSRange(text.startIndex..., in: text)
                if expression.firstMatch(in: text, range: range) != nil { return false }

            case .domain:
                if case .external(let external)? = post.embed,
                   external.host.localizedCaseInsensitiveContains(rule.value) { return false }

            case .handle:
                if post.author.handle.localizedCaseInsensitiveContains(rule.value) { return false }

            case .selfHostedOnly:
                // Unknown origin is kept: absence of an answer is not a verdict.
                if let origin, origin.isBlueskyHosted { return false }
            }
        }
        return true
    }

    private func persist() {
        recompile()
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }

    private func recompile() {
        compiled.removeAll()
        for rule in rules where rule.kind == .regex {
            compiled[rule.id] = try? NSRegularExpression(pattern: rule.value, options: [.caseInsensitive])
        }
    }

    /// Reports whether a pattern would compile, for inline validation in the editor.
    static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
