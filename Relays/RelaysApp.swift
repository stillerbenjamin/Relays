//
//  RelaysApp.swift
//  Relays
//
//  Created by Benjamin Stiller on 29.08.26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct RelaysApp: App {
    @State private var app = AppModel()
    @State private var settings = AppSettings()
    @State private var notifications = NotificationService()
    @State private var reachability = Reachability()

    init() {
        FontLoader.registerBundledFonts()
        // Has to happen during launch, not in a task afterwards.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(settings)
                .environment(notifications)
                .environment(reachability)
                .task {
                    reachability.start()
                    // A tapped notification lands on the alerts — and goes
                    // through the same door as the tab bar, so what was just
                    // read is marked read. It used to set the tab directly and
                    // leave the dot standing.
                    notifications.onOpen = {
                        app.selectedTab = .notifications
                        Task { await app.markNotificationsRead(badging: notifications) }
                    }
                    await notifications.refreshPermission()
                    BackgroundRefresh.configure(app: app, notifications: notifications,
                                                settings: settings)
                    BackgroundRefresh.schedule(settings: settings)
                }
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 860)
        #endif
    }
}

extension View {
    /// Everything the app installs at launch, in one place.
    ///
    /// A preview that misses one of these does not fail to compile — it crashes
    /// when the view that needs it appears, and Xcode reports it as "failed to
    /// launch", which points nowhere near the cause. Adding a new environment
    /// object means adding it here, and every preview has it.
    ///
    /// Deliberately not behind `#if DEBUG`: `#Preview` blocks are compiled in
    /// Release too, so a debug-only helper they call breaks the archive — and
    /// the archive is the one build nobody makes until the day it matters.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environment(AppModel())
            .environment(AppSettings())
            .environment(NotificationService())
            .environment(Reachability())
    }
}

/// Watches the system text size. Navigation state lives in AppModel, so the
/// rebuild on a font, theme or language change keeps the user where they were.
///
/// The rebuild itself is crossfaded: a ground colour swapping mid-animation is
/// what makes a theme switch feel abrupt, so both the colour and the replaced
/// hierarchy are animated across the same beat.
struct RootView: View {
    @Environment(AppSettings.self) private var settings

    #if os(macOS)
    private static let minimumWidth: CGFloat = 460
    private static let minimumHeight: CGFloat = 560
    #endif

    var body: some View {
        ZStack {
            // Only iOS has a safe area worth ignoring. On macOS the modifier
            // pushes the view past the window, and the window follows it.
            #if os(iOS)
            Theme.Palette.background.ignoresSafeArea()
            #else
            Theme.Palette.background
            #endif

            ContentView()
                .id(settings.renderToken)
                .transition(.opacity)
        }
        #if os(macOS)
        // A window takes its opening size from the content's ideal one. Without
        // an ideal, SwiftUI opens as wide as the screen and `defaultSize` on the
        // scene is quietly ignored.
        // Both an ideal and a maximum have to be there. With no ideal the window
        // opens as wide as the screen; with no maximum the content cannot grow
        // when the window is dragged. Given both, SwiftUI opens at the minimum —
        // which is why the minimum is a width the app actually reads at.
        .frame(minWidth: Self.minimumWidth, idealWidth: 480, maxWidth: .infinity,
               minHeight: Self.minimumHeight, idealHeight: 860, maxHeight: .infinity)
        #endif
        .animation(.easeInOut(duration: 0.3), value: settings.renderToken)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(
            for: UIContentSizeCategory.didChangeNotification)) { _ in
            settings.refreshDynamicType()
        }
        #endif
    }
}
