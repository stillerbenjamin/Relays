//
//  BackgroundRefresh.swift
//  Relays
//
//  Periodic check-ins while the app is not open. iOS decides when these run and
//  how often; the schedule below is a request, not a promise.
//

import Foundation
#if canImport(BackgroundTasks) && os(iOS)
@preconcurrency import BackgroundTasks
#endif

@MainActor
enum BackgroundRefresh {

    /// Read from `register()`, which has to run before the app is on the main
    /// actor. A constant string needs no isolation to be read safely.
    nonisolated static let taskIdentifier = "com.stillerbenjamin.Relays.refresh"

    /// What the handler works with, filled in once the app has its objects.
    private static var context: (app: AppModel, notifications: NotificationService, settings: AppSettings)?

    /// Must run before the app finishes launching — iOS terminates the process if
    /// a handler is registered any later. It therefore takes no arguments; the
    /// objects arrive through `configure` and are only needed when a task fires.
    nonisolated static func register() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }

            // The task object itself never crosses to another actor: it is not
            // Sendable, and sending it is a data race whatever the deadline
            // pressure. What crosses is a Bool coming back.
            let work = Task { @MainActor in await gather() }
            refresh.expirationHandler = { work.cancel() }

            Task {
                let delivered = await work.value
                refresh.setTaskCompleted(success: delivered)
            }
        }
        #endif
    }

    static func configure(app: AppModel, notifications: NotificationService, settings: AppSettings) {
        context = (app, notifications, settings)
    }

    static func schedule(settings: AppSettings) {
        #if canImport(BackgroundTasks) && os(iOS)
        guard settings.notificationsEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    #if canImport(BackgroundTasks) && os(iOS)
    /// The whole of the background turn, with nothing in it that belongs to the
    /// scheduler. Returns whether it got through.
    @MainActor
    private static func gather() async -> Bool {
        guard let context else { return false }

        // Always ask for the next slot first: a task that ends without
        // rescheduling is a task that never runs again.
        schedule(settings: context.settings)

        await context.app.checkForNotifications(delivering: context.notifications,
                                                settings: context.settings)
        return !Task.isCancelled
    }
    #endif
}
