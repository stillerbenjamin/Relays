//
//  NotificationService.swift
//  Relays
//
//  Notifications without a server of our own: the app checks in the background
//  and delivers what it finds locally. Remote push would need a service that
//  watches the firehose and talks to APNs; the registration for that is prepared
//  but does nothing until such a service exists.
//

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    enum Permission: Equatable {
        case unknown, granted, denied
    }

    private(set) var permission: Permission = .unknown
    /// The newest notification the reader has already been told about — for the
    /// account currently signed in.
    private var lastSeen: Date = Date()
    /// Whose watermark that is. Nil before anybody has signed in.
    private(set) var account: String?

    private let centre = UNUserNotificationCenter.current()
    private let defaults = NotificationService.store()

    /// One watermark per account. It used to be a single device-wide key, which
    /// meant switching to an account whose notifications were older than the
    /// first account's watermark delivered nothing, ever, with no way to notice.
    private static func key(for did: String) -> String {
        "notifications.lastDelivered." + did
    }

    /// A test process gets its own store, as `AppSettings` does — running the
    /// suite must not move somebody's real watermark.
    private static func store() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "Relays").tests")
                ?? .standard
        }
        #endif
        return .standard
    }

    override init() {
        super.init()
        // Without a delegate the system drops every notification that arrives
        // while the app is in front — which is exactly when this app looks for
        // them. Nothing was ever shown.
        centre.delegate = self
    }

    // MARK: - Whose notifications these are

    /// Signing in, or switching accounts. The watermark follows the account, and
    /// a first sight of one starts at now rather than at the beginning of time.
    func use(account did: String?) {
        guard did != account else { return }
        account = did
        guard let did else {
            lastSeen = Date()
            return
        }
        let stored = defaults.double(forKey: Self.key(for: did))
        lastSeen = stored > 0 ? Date(timeIntervalSince1970: stored) : Date()
    }

    /// Moves the watermark to now without delivering anything — what switching
    /// notifications on has to do, or the first run afterwards would post every
    /// notification since they were switched off.
    func catchUp() {
        lastSeen = Date()
        persistWatermark()
    }

    private func persistWatermark() {
        guard let account else { return }
        defaults.set(lastSeen.timeIntervalSince1970, forKey: Self.key(for: account))
    }

    // MARK: - While the app is open

    /// Show it anyway. The app fetches on becoming active, so almost everything
    /// it finds would otherwise be posted into a window the system hides.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentation
    }

    /// Named so it can be checked: `UNNotification` cannot be built by hand.
    static let foregroundPresentation: UNNotificationPresentationOptions = [.banner, .list, .sound]

    /// Tapping one takes the reader to the alerts, and clears what they have
    /// just been shown.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        onOpen?()
        await clearDelivered()
    }

    /// Set by the app so a tapped notification can move the reader somewhere.
    var onOpen: (@MainActor () -> Void)?

    // MARK: - Permission

    func refreshPermission() async {
        let settings = await centre.notificationSettings()
        permission = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    /// Asked for at the moment someone turns notifications on, not at launch —
    /// a prompt without context is a prompt that gets denied.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permission = granted ? .granted : .denied
        // No `registerForRemoteNotifications()` here. There is no
        // `aps-environment` entitlement and no app delegate to receive a token,
        // so the call could only fail silently — it did, for months.
        return granted
    }

    // MARK: - Delivering what was found

    /// Turns notifications from the network into local ones, newest first, and
    /// remembers how far it has come so nothing is shown twice.
    /// `kinds` is the account's own preferences; `settings` carries only the
    /// local master switch, which is tied to the OS permission and has no server
    /// equivalent.
    func deliver(_ notifications: [ATNotification],
                 kinds: NotificationKinds,
                 settings: AppSettings) async {
        guard permission == .granted, settings.notificationsEnabled else { return }

        let fresh = Self.selecting(from: notifications, settings: kinds, since: lastSeen)
        guard !fresh.isEmpty else { return }

        // A backlog is not worth twenty-five banners. Somebody who switches
        // notifications on after a quiet week used to get the whole fetch at
        // once, in a loop, with no cap.
        let shown = fresh.suffix(Self.burstLimit)
        let hidden = fresh.count - shown.count

        // Each is delivered on its own. iOS groups them by thread, so a run of
        // likes stacks into one entry rather than filling the screen.
        for (item, _) in shown {
            let detail = item.record?.text.isEmpty == false
                ? ": \(item.record!.text.prefix(120))"
                : ""
            await post(title: item.author.name,
                       body: "\(item.verb)\(detail)",
                       identifier: item.id,
                       thread: item.reason)
        }

        if hidden > 0 {
            await post(title: L10n.t(.tabNotifications),
                       body: L10n.t(.notifyMore, String(hidden)),
                       identifier: "backlog",
                       thread: "backlog")
        }

        if let newest = fresh.last?.1 {
            lastSeen = newest
            persistWatermark()
        }
    }

    /// How many banners one round may post before the rest becomes a single
    /// line. Five is about what a lock screen shows without becoming a wall.
    static let burstLimit = 5

    /// What is worth telling somebody about: the kinds they asked for, newer
    /// than the last one they were told about, oldest first so the newest ends
    /// up on top of the stack.
    static func selecting(from notifications: [ATNotification],
                          settings kinds: NotificationKinds,
                          since: Date) -> [(ATNotification, Date)] {
        notifications
            .filter { kinds.wantsNotification(ofKind: $0.reason) }
            .compactMap { item -> (ATNotification, Date)? in
                guard let date = RelativeTime.date(from: item.indexedAt), date > since else { return nil }
                return (item, date)
            }
            .sorted { $0.1 < $1.1 }
    }

    private func post(title: String, body: String, identifier: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Likes stack with likes, replies with replies.
        content.threadIdentifier = thread

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await centre.add(request)
    }

    /// The count on the app icon, kept in step with the unread badge in the app.
    func setBadge(_ count: Int) async {
        try? await centre.setBadgeCount(max(0, count))
    }

    /// Called when someone opens the app: whatever is on screen has been seen.
    /// Takes the banners down and leaves the badge alone. Coming forward used
    /// to zero the badge and then set it again from the fetch a moment later.
    func clearBanners() {
        centre.removeAllDeliveredNotifications()
    }

    func clearDelivered() async {
        centre.removeAllDeliveredNotifications()
        await setBadge(0)
    }
}
