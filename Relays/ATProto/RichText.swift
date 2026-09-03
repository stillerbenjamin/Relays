//
//  RichText.swift
//  Relays
//
//  Facet detection while composing and segmentation while rendering.
//  Facets index UTF-8 bytes, not characters — the conversion here relies on that.
//

import Foundation

enum RichText {

    // MARK: - Rendering

    enum Segment: Identifiable, Hashable {
        case text(String)
        case link(text: String, url: URL)
        case mention(text: String, did: String)
        case tag(text: String, tag: String)

        var id: String {
            switch self {
            case .text(let t): return "t:\(t.hashValue)"
            case .link(let t, let u): return "l:\(t.hashValue):\(u.absoluteString)"
            case .mention(let t, let d): return "m:\(t.hashValue):\(d)"
            case .tag(let t, let g): return "g:\(t.hashValue):\(g)"
            }
        }
    }

    /// Splits the text into renderable segments along its facets.
    static func segments(text: String, facets: [Facet]?) -> [Segment] {
        let bytes = Array(text.utf8)
        guard let facets, !facets.isEmpty else { return [.text(text)] }

        let sorted = facets
            .filter { $0.index.byteStart >= 0 && $0.index.byteEnd <= bytes.count && $0.index.byteStart < $0.index.byteEnd }
            .sorted { $0.index.byteStart < $1.index.byteStart }

        var segments: [Segment] = []
        var cursor = 0

        for facet in sorted {
            guard facet.index.byteStart >= cursor else { continue }
            if facet.index.byteStart > cursor {
                segments.append(.text(string(bytes, cursor, facet.index.byteStart)))
            }
            let slice = string(bytes, facet.index.byteStart, facet.index.byteEnd)
            switch facet.features.first {
            case .link(let uri):
                if let url = URL(string: uri) {
                    segments.append(.link(text: slice, url: url))
                } else {
                    segments.append(.text(slice))
                }
            case .mention(let did):
                segments.append(.mention(text: slice, did: did))
            case .tag(let tag):
                segments.append(.tag(text: slice, tag: tag))
            default:
                segments.append(.text(slice))
            }
            cursor = facet.index.byteEnd
        }

        if cursor < bytes.count {
            segments.append(.text(string(bytes, cursor, bytes.count)))
        }
        return segments
    }

    private static func string(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    // MARK: - Composing

    /// Detects URLs and hashtags in a draft so the network links them.
    /// Mentions are added by the client, which can resolve a handle to a DID.
    static func detectFacets(in text: String) -> [Facet] {
        var facets: [Facet] = []
        let ns = text as NSString

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let url = match.url, url.scheme == "http" || url.scheme == "https" else { continue }
                guard let range = Range(match.range, in: text) else { continue }
                facets.append(Facet(index: byteSlice(of: range, in: text),
                                    features: [.link(uri: url.absoluteString)]))
            }
        }

        let tagPattern = try? NSRegularExpression(pattern: "(?<![\\w#])#([\\p{L}\\p{N}_]{1,64})")
        tagPattern?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let full = Range(match.range, in: text),
                  let name = Range(match.range(at: 1), in: text) else { return }
            facets.append(Facet(index: byteSlice(of: full, in: text),
                                features: [.tag(String(text[name]))]))
        }

        return facets.sorted { $0.index.byteStart < $1.index.byteStart }
    }

    /// The @handles in a draft, with the byte range each one occupies.
    /// A handle needs a dot: "@alice" is a word, "@alice.bsky.social" is an account.
    static func mentionCandidates(in text: String) -> [(handle: String, index: Facet.ByteSlice)] {
        let pattern = try? NSRegularExpression(
            pattern: "(?<![\\w@])@([a-zA-Z0-9][a-zA-Z0-9-]*(?:\\.[a-zA-Z0-9-]+)+)")
        var found: [(handle: String, index: Facet.ByteSlice)] = []

        pattern?.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, _ in
            guard let match,
                  let full = Range(match.range, in: text),
                  let handle = Range(match.range(at: 1), in: text) else { return }
            // Trailing punctuation is not part of a handle.
            var name = String(text[handle])
            while let last = name.last, last == "." || last == "-" { name.removeLast() }
            guard name.contains(".") else { return }
            found.append((name, byteSlice(of: full, in: text)))
        }
        return found
    }

    private static func byteSlice(of range: Range<String.Index>, in text: String) -> Facet.ByteSlice {
        let start = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound.samePosition(in: text.utf8) ?? text.utf8.startIndex)
        let end = text.utf8.distance(from: text.utf8.startIndex, to: range.upperBound.samePosition(in: text.utf8) ?? text.utf8.endIndex)
        return Facet.ByteSlice(byteStart: start, byteEnd: end)
    }

    /// Bluesky counts graphemes (300 maximum).
    static func graphemeCount(_ text: String) -> Int { text.count }
}

// MARK: - Time formatting

enum RelativeTime {
    /// From settings: absolute instead of relative timestamps.
    static var absolute = false

    private static let parsers: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        for parser in parsers {
            if let date = parser.date(from: string) { return date }
        }
        return nil
    }

    /// Compact form such as "3m", "5h", "2d" — or absolute, depending on settings.
    static func short(_ string: String?) -> String {
        guard let date = date(from: string) else { return "" }
        if absolute { return absoluteString(date, includeTime: true) }

        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return L10n.t(.timeNow)
        case ..<3600: return "\(Int(seconds / 60))\(L10n.t(.timeMinute))"
        case ..<86_400: return "\(Int(seconds / 3600))\(L10n.t(.timeHour))"
        case ..<604_800: return "\(Int(seconds / 86_400))\(L10n.t(.timeDay))"
        default: return absoluteString(date, includeTime: false)
        }
    }

    /// The other direction: how long something still has. `short` clamps the
    /// past, so a future date would come out of it as "now".
    ///
    /// Rounded up, not down. Time left counts down through a unit — truncating
    /// would print "5d" for all but the first moments of the sixth day.
    static func remaining(until date: Date) -> String {
        let seconds = max(0, date.timeIntervalSinceNow)
        switch seconds {
        case ..<60: return L10n.t(.timeNow)
        case ..<3600: return "\(Int(ceil(seconds / 60)))\(L10n.t(.timeMinute))"
        case ..<86_400: return "\(Int(ceil(seconds / 3600)))\(L10n.t(.timeHour))"
        default: return "\(Int(ceil(seconds / 86_400)))\(L10n.t(.timeDay))"
        }
    }

    private static func absoluteString(_ date: Date, includeTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Format.locale
        formatter.dateFormat = L10n.language.resolved == .de
            ? (includeTime ? "dd.MM. HH:mm" : "dd.MM.yy")
            : (includeTime ? "MMM d, HH:mm" : "MMM d, yy")
        return formatter.string(from: date)
    }
}

// MARK: - Auto-linking for plain text

extension RichText {
    /// Profile bios arrive as plain text — the network stores no facets for them.
    /// URLs, bare domains and @handles are detected locally so they stay tappable.
    static func autoLinkedSegments(in text: String) -> [Segment] {
        var found: [(range: Range<String.Index>, segment: Segment)] = []
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: fullRange) {
                guard let url = match.url, let range = Range(match.range, in: text) else { continue }
                guard url.scheme == "http" || url.scheme == "https" else { continue }
                found.append((range, .link(text: String(text[range]), url: url)))
            }
        }

        // Hashtags, so a tag in a bio leads somewhere just as it does in a post.
        let tagPattern = try? NSRegularExpression(pattern: "(?<![\\w#])#([\\p{L}\\p{N}_]{1,64})")
        tagPattern?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match,
                  let full = Range(match.range, in: text),
                  let name = Range(match.range(at: 1), in: text) else { return }
            guard !found.contains(where: { $0.range.overlaps(full) }) else { return }
            found.append((full, .tag(text: String(text[full]), tag: String(text[name]))))
        }

        // Handles such as @alice.bsky.social — the trailing domain part is required.
        let handlePattern = try? NSRegularExpression(pattern: "@([a-zA-Z0-9][a-zA-Z0-9-]*\\.[a-zA-Z0-9.-]+[a-zA-Z])")
        handlePattern?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match,
                  let full = Range(match.range, in: text),
                  let handle = Range(match.range(at: 1), in: text) else { return }
            guard !found.contains(where: { $0.range.overlaps(full) }) else { return }
            found.append((full, .mention(text: String(text[full]), did: String(text[handle]))))
        }

        guard !found.isEmpty else { return [.text(text)] }

        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        var segments: [Segment] = []
        var cursor = text.startIndex
        for item in found where item.range.lowerBound >= cursor {
            if item.range.lowerBound > cursor {
                segments.append(.text(String(text[cursor..<item.range.lowerBound])))
            }
            segments.append(item.segment)
            cursor = item.range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(.text(String(text[cursor...])))
        }
        return segments
    }
}
