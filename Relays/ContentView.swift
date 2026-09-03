//
//  ContentView.swift
//  Relays
//
//  Created by Benjamin Stiller on 29.08.26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // The ground has to cover the whole window at every phase. On macOS
            // `ignoresSafeArea` lays the colour out past the window instead of
            // filling it, and what stays behind is whatever was drawn last —
            // which is how the sign-in screen went on showing under the app.
            #if os(iOS)
            Theme.Palette.background.ignoresSafeArea()
            #else
            Theme.Palette.background
            #endif

            // Each state is its own view with its own identity. Without the ids
            // the view being left could stay in the hierarchy — on macOS the
            // sign-in screen went on showing behind the signed-in app.
            switch app.phase {
            case .launching:
                AuthGateView(showsLogin: false)
                    .id("launching")
                    .transition(.opacity)
            case .signedOut:
                AuthGateView(showsLogin: true)
                    .id("signedOut")
                    .transition(.opacity)
            case .signedIn:
                HomeView()
                    .id("signedIn")
                    .transition(.opacity)
            }
        }
        // The crossfade between whole app states is an iOS flourish. On macOS it
        // is where a view being left could linger — and a lingering sign-in
        // screen behind the app is worse than a missing fade.
        #if os(iOS)
        .animation(.easeInOut(duration: 0.35), value: app.phase)
        #endif
        .relaysColorScheme()
        .withInAppBrowser()
        .withOverlays()
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, app.phase == .signedIn else {
                if phase == .background { BackgroundRefresh.schedule(settings: settings) }
                return
            }
            Task {
                // Somebody may have granted or withdrawn it in System Settings
                // while the app was away; it used to be read once at launch and
                // believed for the whole session.
                await notifications.refreshPermission()
                // Only the banners go, not the badge — clearing the badge here
                // made it blink to nothing and straight back.
                notifications.clearBanners()
                await app.checkForNotifications(delivering: notifications, settings: settings)
                // Once, and only after a read that actually succeeded.
                await app.migrateNotificationChoices(from: settings)
            }
        }
        // Background refresh exists only on iOS, and even there it runs when the
        // system feels like it. While the app is open — which on a Mac is the
        // only time it runs at all — it looks for itself.
        .task(id: app.phase) {
            guard app.phase == .signedIn else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled, settings.notificationsEnabled else { continue }
                await app.checkForNotifications(delivering: notifications, settings: settings)
            }
        }
        .task {
            guard app.phase == .launching else { return }
            // Keep the launch screen from flashing; bootstrap() flips the phase afterwards.
            try? await Task.sleep(for: .milliseconds(700))
            await app.bootstrap()
        }
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
