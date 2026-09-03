//
//  FollowButton.swift
//  Relays
//

import SwiftUI

/// Follows or unfollows an account. Hidden for the signed-in account itself,
/// since there is nothing to do there.
struct FollowButton: View {
    let profile: ActorProfile
    var compact = false

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings

    private var isFollowing: Bool { app.isFollowing(profile) }
    private var isSelf: Bool { profile.did == app.session?.did }

    var body: some View {
        if !isSelf {
            Button {
                Haptics.tap(enabled: settings.haptics)
                Task { await app.toggleFollow(profile) }
            } label: {
                Text(isFollowing ? L(.unfollow) : L(.follow))
                    .font(Theme.Font.ui(compact ? 13 : 15, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isFollowing ? Theme.Palette.textPrimary : Theme.Palette.onAccent)
                    .padding(.horizontal, compact ? 12 : 18)
                    .frame(height: compact ? 30 : 36)
                    .background(
                        Capsule()
                            .fill(isFollowing ? Theme.Palette.surface : Theme.Palette.accent)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isFollowing ? Theme.Palette.hairline : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: isFollowing)
            .onAppear { app.register(profile) }
            .accessibilityLabel(isFollowing ? L(.unfollowAction) : L(.follow))
            .accessibilityValue("@\(profile.handle)")
        }
    }
}
