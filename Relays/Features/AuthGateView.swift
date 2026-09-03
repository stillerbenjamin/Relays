//
//  AuthGateView.swift
//  Relays
//
//  Launch screen and sign-in. The wordmark travels from the centre to the top
//  during the transition — the two states match the reference screenshots.
//

import SwiftUI

struct AuthGateView: View {
    let showsLogin: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Wordmark(size: 34)

                if showsLogin {
                    SignInForm()
                        .padding(.top, 34)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 0)
            // The form sits slightly above centre, which reads as balanced. The
            // launch screen has nothing below it, so its wordmark is centred.
            if showsLogin { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Behind the ground colour's own layer, so the traces sit on the
            // theme rather than replacing it.
            ZStack {
                Theme.Palette.background
                // Only once the form is up: the launch screen is not the place
                // to open a connection.
                if showsLogin {
                    LiveLoginBackdrop(progress: 1)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.9), value: showsLogin)
        }
        .animation(.easeInOut(duration: 0.45), value: showsLogin)
    }
}

/// Credentials form, shared by the launch screen and the add-account sheet.
struct SignInForm: View {
    var onFinished: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

    @State private var identifier = ""
    @State private var appPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var lookup = HomeServerLookup()

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty && !appPassword.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 7) {
                MonoField(icon: "at",
                          placeholder: L(.authIdentifier),
                          text: $identifier,
                          submitLabel: .next)

                // Where this account lives, before anybody has typed a password.
                // The answer is public; no other client says it out loud.
                HomeServerLine(state: lookup.state)
            }
            .onChange(of: identifier) { _, typed in lookup.lookUp(typed) }
            .animation(.easeOut(duration: 0.2), value: lookup.state)

            MonoField(icon: "key",
                      placeholder: L(.authPassword),
                      text: $appPassword,
                      isSecure: true,
                      submitLabel: .go,
                      onSubmit: submit)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.Palette.danger.opacity(0.12))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            MonoButton(title: L(.authConnect), isLoading: isSubmitting, isEnabled: canSubmit, action: submit)
                .padding(.top, 4)

        }
        .animation(.easeOut(duration: 0.2), value: errorMessage)
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await app.signIn(identifier: identifier, appPassword: appPassword)
                onFinished?()
            } catch {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
                appPassword = ""
            }
            isSubmitting = false
        }
    }
}

/// Adding a second account: same form, presented as a sheet.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.accountAdd))
                    .font(Theme.Font.ui(12, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 52)
            Hairline()

            SignInForm { dismiss() }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.top, 22)

            Spacer()
        }
        .relaysBackground()
        .relaysColorScheme()
    }
}

#Preview("Splash") {
    AuthGateView(showsLogin: false).previewEnvironment()
}

#Preview("Login") {
    AuthGateView(showsLogin: true).previewEnvironment()
}
