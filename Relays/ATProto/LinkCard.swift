//
//  LinkCard.swift
//  Relays
//
//  The card a post carries when it links somewhere: title, description and a
//  picture, stored in the post as `app.bsky.embed.external`.
//
//  The app could draw these from the start and never made one — so a link
//  posted from Relays arrived as bare text while the same link from any other
//  client arrived as a card.
//
//  Relays reads the page itself rather than asking a card service. Bluesky's own
//  client sends every URL you type to `cardyb.bsky.app`; doing it here means the
//  only party that learns what is being composed is the site being linked to,
//  which would learn it the moment the post went out anyway.
//

import Foundation

/// What a page says about itself. Everything is optional: a page with no Open
/// Graph tags still makes a card, it just carries less.
struct LinkCard: Equatable, Sendable {
    var uri: String
    var title: String?
    var description: String?
    var imageURL: URL?

    var isWorthShowing: Bool {
        title?.isEmpty == false || description?.isEmpty == false || imageURL != nil
    }
}

enum LinkCardReader {

    /// Bytes to read before giving up. The tags are in the head; a page that has
    /// not declared itself in the first quarter-megabyte is not going to.
    static let limit = 256 * 1024

    /// Reads a page's own description of itself.
    ///
    /// Open Graph first, then Twitter's names, then the plain HTML `<title>` and
    /// meta description — in that order, because that is the order of how
    /// deliberately each was written for this purpose.
    static func card(from html: String, url: URL) -> LinkCard {
        var card = LinkCard(uri: url.absoluteString)

        card.title = content(of: ["og:title", "twitter:title"], in: html)
            ?? firstMatch(#"<title[^>]*>([^<]{1,300})</title>"#, in: html)
        card.description = content(of: ["og:description", "twitter:description",
                                        "description"], in: html)

        if let image = content(of: ["og:image", "og:image:url", "twitter:image"], in: html) {
            // A relative path is legal here and common. Resolving it against the
            // page is the difference between a card and a broken one.
            card.imageURL = URL(string: image, relativeTo: url)?.absoluteURL
        }
        return card
    }

    /// `property=` and `name=` are both used in the wild, and the attributes
    /// appear in either order, so both spellings are tried for each key.
    private static func content(of keys: [String], in html: String) -> String? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            // Two things have to hold at once. The closing quote must be the
            // one that opened, or a title like "From Twitter's names" ends at
            // the apostrophe — hence the backreference. And the value must not
            // cross a `>`, or a lazy match simply runs on into the next tag
            // until it finds what it wants. A real `>` inside an attribute is
            // written `&gt;`, which the entity pass below turns back.
            let patterns: [(String, Int)] = [
                (#"<meta[^>]+(?:property|name)\s*=\s*(["'])"# + escaped
                    + #"\1[^>]*?content\s*=\s*(["'])([^>]*?)\2"#, 3),
                (#"<meta[^>]+content\s*=\s*(["'])([^>]*?)\1[^>]*?(?:property|name)\s*=\s*(["'])"#
                    + escaped + #"\3"#, 2)
            ]
            for (pattern, group) in patterns {
                if let found = firstMatch(pattern, in: html, group: group), !found.isEmpty {
                    return found
                }
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern,
                                                        options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text)
        else { return nil }
        return decoded(String(text[range])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The five entities that actually turn up in a title, plus numeric ones.
    /// A full entity table would be a library; this is what pages use.
    static func decoded(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                                    ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
                                    ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
                                    ("&hellip;", "…")] {
            result = result.replacingOccurrences(of: entity, with: character,
                                                 options: .caseInsensitive)
        }
        return result
    }

    /// The first link in what somebody has typed, which is the one a card is
    /// made for. Reuses the facet detector so the composer and the record agree
    /// about what counts as a link.
    static func firstLink(in text: String) -> URL? {
        let bytes = Array(text.utf8)
        for facet in RichText.detectFacets(in: text) {
            for feature in facet.features {
                guard case .link(let uri) = feature else { continue }
                guard facet.index.byteStart >= 0, facet.index.byteEnd <= bytes.count else { continue }
                if let url = URL(string: uri), url.scheme == "https" || url.scheme == "http" {
                    return url
                }
            }
        }
        return nil
    }
}
