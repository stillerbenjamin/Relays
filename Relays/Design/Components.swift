//
//  Components.swift
//  Relays
//

import SwiftUI

/// The input field from the reference screenshots: dark surface, SF Symbol on the left,
/// monospaced placeholder in grey.
struct MonoField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 16)

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .tint(Theme.Palette.accent)
            .focused($focused)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.Metric.fieldHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                .stroke(focused ? Theme.Palette.accent : Theme.Palette.hairline, lineWidth: focused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var prompt: Text {
        Text(placeholder)
            .font(Theme.Font.body)
            .foregroundColor(Theme.Palette.textTertiary)
    }
}

/// The "Relays" wordmark — identical on the launch and sign-in screens.
struct Wordmark: View {
    var size: CGFloat = 26

    var body: some View {
        Text("Relays")
            .font(Theme.Font.ui(size, .semibold))
            .tracking(Theme.Metric.wordmarkTracking)
            .foregroundStyle(Theme.Palette.textPrimary)
    }
}

/// Flat, borderless button in the monospaced style.
struct MonoButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(Theme.Font.ui(15, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Palette.onAccent)
                }
            }
            .foregroundStyle(isEnabled ? Theme.Palette.onAccent : Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metric.fieldHeight)
            .background(
                Capsule().fill(isEnabled ? Theme.Palette.accent : Theme.Palette.surface)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// Avatar falling back to the first letter of the handle.
struct AvatarView: View {
    let url: URL?
    let seed: String
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 0.5))
    }

    private var placeholder: some View {
        ZStack {
            Theme.Palette.surfaceRaised
            Text(String(seed.trimmingCharacters(in: CharacterSet(charactersIn: "@")).prefix(1)).uppercased())
                .font(Theme.Font.ui(size * 0.42, .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// Thin separator between list rows.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Shared empty and error state.
struct StateMessage: View {
    let text: String
    var systemImage: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Text(text)
                .font(Theme.Font.ui(16))
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let retry {
                Button(L(.retry), action: retry)
                    .font(Theme.Font.ui(15, .medium))
                    .foregroundStyle(Theme.Palette.link)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 64)
    }
}


/// Says the app is offline, where a reader would otherwise blame the server or
/// themselves. It replaces no error message — it explains the ones that follow.
struct OfflineNotice: View {
    @Environment(Reachability.self) private var reachability

    var body: some View {
        if !reachability.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11))
                Text(L(.offlineBanner))
                    .font(Theme.Font.ui(12))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.surface)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
