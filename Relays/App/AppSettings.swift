//
//  AppSettings.swift
//  Relays
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum TextSizeOption: String, CaseIterable, Identifiable, Codable {
    case small, medium, large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }

    var label: String {
        switch self {
        case .small: return L(.settingsTextSizeSmall)
        case .medium: return L(.settingsTextSizeMedium)
        case .large: return L(.settingsTextSizeLarge)
        }
    }
}

/// The part of the settings the delivery rule needs. Small on purpose: it lets
/// the rule be checked without building a whole settings store.
@MainActor
protocol NotificationKinds {
    func wantsNotification(ofKind reason: String) -> Bool
}

@MainActor
@Observable
final class AppSettings {

    // Darstellung
    var theme: AppTheme { didSet { persist(); apply() } }
    var language: AppLanguage { didSet { persist(); apply() } }
    var textSize: TextSizeOption { didSet { persist(); apply() } }
    var slimFonts: Bool { didSet { persist(); apply() } }
    var followDynamicType: Bool { didSet { persist(); apply() } }
    var compactMode: Bool { didSet { persist() } }
    var showImages: Bool { didSet { persist() } }
    var showAltBadge: Bool { didSet { persist() } }
    var showCounts: Bool { didSet { persist() } }
    var showPDSOrigin: Bool { didSet { persist() } }
    var absoluteTime: Bool { didSet { persist(); apply() } }

    // Feed
    var hideReposts: Bool { didSet { persist() } }
    var hideReplies: Bool { didSet { persist() } }
    var autoRefresh: Bool { didSet { persist() } }
    var relayPulse: Bool { didSet { persist() } }

    // Benachrichtigungen
    var notificationsEnabled: Bool { didSet { persist() } }
    /// Set once the device's retired notification switches have been carried
    /// up to the account.
    var notificationsMigrated: Bool { didSet { persist() } }

    // Verhalten
    var openLinksInApp: Bool { didSet { persist() } }
    var haptics: Bool { didSet { persist() } }

    /// Changes with every setting that applies globally (type, language).
    /// The interface depends on it and rebuilds when it moves.
    private(set) var renderToken = 0

    private let defaults = AppSettings.store()

    /// Where the settings live.
    ///
    /// The unit tests run inside the app, so `UserDefaults.standard` there is
    /// the settings of whoever owns the machine — and several tests set a
    /// theme, a text size or a filter. They were writing them for real: running
    /// the suite on a Mac that also runs Relays changed the app for its owner,
    /// and a snapshot came out looking like that person's settings rather than
    /// the ones the test asked for. A test process gets its own store.
    private static func store() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            guard let scratch = UserDefaults(suiteName: Self.scratchSuite) else { return .standard }
            _ = emptiedOnce
            return scratch
        }
        #endif
        return .standard
    }

    #if DEBUG
    private static var scratchSuite: String {
        "\(Bundle.main.bundleIdentifier ?? "Relays").tests"
    }

    /// A store that survives between runs would carry one run's settings into
    /// the next, and a test that starts from "the documented default" would be
    /// starting from whatever ran last. Emptied once per process.
    private static let emptiedOnce: Void = {
        UserDefaults.standard.removePersistentDomain(forName: scratchSuite)
    }()

    /// The store the settings actually read. A test that wants a known starting
    /// point clears this one — clearing `UserDefaults.standard` stopped meaning
    /// anything the moment a test process got its own.
    static var testingStore: UserDefaults {
        UserDefaults(suiteName: scratchSuite) ?? .standard
    }
    #endif

    init() {
        #if DEBUG
        // A UI test needs to know what it is looking at. With this flag the app
        // starts from a known theme, size and language instead of whatever the
        // simulator happened to keep from the last run.
        if let forced = Self.uiTestingOverrides() {
            theme = forced.theme
            language = .en
            textSize = forced.textSize
            slimFonts = true
            followDynamicType = false
            compactMode = false
            showImages = true
            showAltBadge = true
            showCounts = true
            showPDSOrigin = true
            absoluteTime = false
            hideReposts = false
            hideReplies = false
            autoRefresh = false
            relayPulse = false
            notificationsEnabled = false
            notificationsMigrated = true
            openLinksInApp = true
            haptics = false
            apply()
            return
        }
        #endif

        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .dark
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .en
        textSize = TextSizeOption(rawValue: defaults.string(forKey: Key.textSize) ?? "") ?? .medium
        slimFonts = defaults.object(forKey: Key.slimFonts) as? Bool ?? true
        followDynamicType = defaults.object(forKey: Key.followDynamicType) as? Bool ?? true
        compactMode = defaults.object(forKey: Key.compactMode) as? Bool ?? false
        showImages = defaults.object(forKey: Key.showImages) as? Bool ?? true
        showAltBadge = defaults.object(forKey: Key.showAltBadge) as? Bool ?? true
        showCounts = defaults.object(forKey: Key.showCounts) as? Bool ?? true
        showPDSOrigin = defaults.object(forKey: Key.showPDSOrigin) as? Bool ?? true
        absoluteTime = defaults.object(forKey: Key.absoluteTime) as? Bool ?? false
        hideReposts = defaults.object(forKey: Key.hideReposts) as? Bool ?? false
        hideReplies = defaults.object(forKey: Key.hideReplies) as? Bool ?? false
        autoRefresh = defaults.object(forKey: Key.autoRefresh) as? Bool ?? true
        relayPulse = defaults.object(forKey: Key.relayPulse) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        notificationsMigrated = defaults.object(forKey: Key.notificationsMigrated) as? Bool ?? false
        openLinksInApp = defaults.object(forKey: Key.openLinksInApp) as? Bool ?? true
        haptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        apply()
    }

    /// Pushes the values into the globally read configuration.
    private func apply() {
        L10n.language = language
        Theme.theme = theme
        Theme.Font.scale = textSize.scale
        Theme.Font.slim = slimFonts
        Theme.Font.dynamicScale = followDynamicType ? Self.systemTextScale() : 1.0
        RelativeTime.absolute = absoluteTime
        renderToken += 1
    }

    /// Reapplies the system text size, e.g. after the user changes it in Settings.
    func refreshDynamicType() {
        guard followDynamicType else { return }
        let updated = Self.systemTextScale()
        guard abs(updated - Theme.Font.dynamicScale) > 0.001 else { return }
        Theme.Font.dynamicScale = updated
        renderToken += 1
    }

    /// UIFontMetrics covers every category including the accessibility sizes;
    /// the cap keeps the monospaced layout from breaking apart.
    private static func systemTextScale() -> CGFloat {
        #if canImport(UIKit) && os(iOS)
        return min(1.45, UIFontMetrics.default.scaledValue(for: 100) / 100)
        #else
        return 1.0
        #endif
    }

    #if DEBUG
    /// Reads the flags a UI test launches with. Nothing outside a test sets them.
    private static func uiTestingOverrides() -> (theme: AppTheme, textSize: TextSizeOption)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-relaysUITesting") else { return nil }

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.index(after: index) < arguments.endIndex else { return nil }
            return arguments[arguments.index(after: index)]
        }
        return (AppTheme(rawValue: value(after: "-relaysTheme") ?? "") ?? .dark,
                TextSizeOption(rawValue: value(after: "-relaysTextSize") ?? "") ?? .medium)
    }
    #endif

    private func persist() {
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(textSize.rawValue, forKey: Key.textSize)
        defaults.set(slimFonts, forKey: Key.slimFonts)
        defaults.set(followDynamicType, forKey: Key.followDynamicType)
        defaults.set(compactMode, forKey: Key.compactMode)
        defaults.set(showImages, forKey: Key.showImages)
        defaults.set(showAltBadge, forKey: Key.showAltBadge)
        defaults.set(showCounts, forKey: Key.showCounts)
        defaults.set(showPDSOrigin, forKey: Key.showPDSOrigin)
        defaults.set(absoluteTime, forKey: Key.absoluteTime)
        defaults.set(hideReposts, forKey: Key.hideReposts)
        defaults.set(hideReplies, forKey: Key.hideReplies)
        defaults.set(autoRefresh, forKey: Key.autoRefresh)
        defaults.set(relayPulse, forKey: Key.relayPulse)
        defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(notificationsMigrated, forKey: Key.notificationsMigrated)
        defaults.set(openLinksInApp, forKey: Key.openLinksInApp)
        defaults.set(haptics, forKey: Key.haptics)
    }

    /// What the four booleans said, for the one migration that reads them. Nil
    /// once they are gone, or when they were all at their default.
    func retiredNotificationChoices() -> [String: Bool]? {
        let keys = ["settings.notifyLikes": "like", "settings.notifyReposts": "repost",
                    "settings.notifyFollows": "follow", "settings.notifyReplies": "reply"]
        var chosen: [String: Bool] = [:]
        for (key, kind) in keys {
            guard let value = defaults.object(forKey: key) as? Bool else { continue }
            chosen[kind] = value
        }
        // All true is the default. Writing it up could only overwrite a choice
        // made deliberately somewhere else.
        guard chosen.values.contains(false) else { return nil }
        return chosen
    }

    func forgetRetiredNotificationChoices() {
        for key in ["settings.notifyLikes", "settings.notifyReposts",
                    "settings.notifyFollows", "settings.notifyReplies"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Filters out reposts or replies when they are unwanted in the feed.
    func passesFeedFilter(_ item: FeedViewPost) -> Bool {
        if hideReposts, case .repost = item.reason { return false }
        if hideReplies, item.reply != nil { return false }
        return true
    }

    private enum Key {
        static let theme = "settings.theme"
        static let language = "settings.language"
        static let textSize = "settings.textSize"
        static let slimFonts = "settings.slimFonts"
        static let followDynamicType = "settings.followDynamicType"
        static let compactMode = "settings.compactMode"
        static let showImages = "settings.showImages"
        static let showAltBadge = "settings.showAltBadge"
        static let showCounts = "settings.showCounts"
        static let showPDSOrigin = "settings.showPDSOrigin"
        static let absoluteTime = "settings.absoluteTime"
        static let hideReposts = "settings.hideReposts"
        static let hideReplies = "settings.hideReplies"
        static let autoRefresh = "settings.autoRefresh"
        static let relayPulse = "settings.relayPulse"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let notificationsMigrated = "settings.notificationsMigrated"
        static let openLinksInApp = "settings.openLinksInApp"
        static let haptics = "settings.haptics"
    }
}
