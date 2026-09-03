//
//  SnapshotSettings.swift
//  RelaysTests
//
//  `AppSettings` reads and writes the host app's UserDefaults, and every set
//  persists straight away. Two things follow, both of which had already
//  happened:
//
//  1. A snapshot drew whatever the machine had saved. This Mac had run the app,
//     so it had compact rows, absolute timestamps and reposts hidden — the same
//     test produced a different picture there than in a clean simulator.
//  2. Taking a snapshot changed the app for whoever owns the machine. The
//     language and theme a snapshot set were simply left behind.
//
//  Everything a snapshot touches is pinned here and handed back afterwards.
//

import Foundation
@testable import Relays

@MainActor
enum SnapshotSettings {

    /// The values a picture depends on, as they were before the test.
    @MainActor
    private struct Saved {
        let theme: AppTheme
        let language: AppLanguage
        let textSize: TextSizeOption
        let followDynamicType: Bool
        let compactMode: Bool
        let showImages: Bool
        let showAltBadge: Bool
        let showCounts: Bool
        let showPDSOrigin: Bool
        let absoluteTime: Bool
        let hideReposts: Bool
        let hideReplies: Bool
        let globalLanguage: AppLanguage

        init(_ s: AppSettings) {
            theme = s.theme; language = s.language; textSize = s.textSize
            followDynamicType = s.followDynamicType; compactMode = s.compactMode
            showImages = s.showImages; showAltBadge = s.showAltBadge
            showCounts = s.showCounts; showPDSOrigin = s.showPDSOrigin
            absoluteTime = s.absoluteTime; hideReposts = s.hideReposts
            hideReplies = s.hideReplies
            globalLanguage = L10n.language
        }

        func restore(to s: AppSettings) {
            s.theme = theme; s.language = language; s.textSize = textSize
            s.followDynamicType = followDynamicType; s.compactMode = compactMode
            s.showImages = showImages; s.showAltBadge = showAltBadge
            s.showCounts = showCounts; s.showPDSOrigin = showPDSOrigin
            s.absoluteTime = absoluteTime; s.hideReposts = hideReposts
            s.hideReplies = hideReplies
            L10n.language = globalLanguage
        }
    }

    /// Runs `body` with settings a picture can be pinned to, and puts the
    /// machine's own back afterwards — including when the test fails.
    static func pinned<T>(theme: AppTheme = .dark,
                          language: AppLanguage = .en,
                          textSize: TextSizeOption = .medium,
                          compact: Bool = false,
                          _ body: (AppSettings) throws -> T) rethrows -> T {
        let settings = AppSettings()
        let saved = Saved(settings)
        defer { saved.restore(to: settings) }

        settings.theme = theme
        settings.language = language
        settings.textSize = textSize
        settings.followDynamicType = false
        settings.compactMode = compact
        settings.showImages = true
        settings.showAltBadge = true
        settings.showCounts = true
        settings.showPDSOrigin = false
        // Relative timestamps, or a snapshot goes stale the day after it is taken.
        settings.absoluteTime = false
        settings.hideReposts = false
        settings.hideReplies = false
        L10n.language = language

        return try body(settings)
    }
}
