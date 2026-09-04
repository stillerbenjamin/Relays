//
//  AppPasswordsView.swift
//  Relays
//
//  The credentials an account is reachable by. Relays signs in with one of
//  these and could neither show them nor take one back — so the app asked for a
//  credential it then hid, and the one place to withdraw it was somebody else's
//  website.
//
//  The screen is honest about one thing it cannot do: `listAppPasswords`
//  returns names and dates, and nothing in the protocol says which password the
//  current session was made with. So Relays cannot mark its own, and says so
//  rather than guessing and being wrong.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppPasswordsModel {
    private(set) var passwords: [AppPassword] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    /// Shown once, right after it is made. The server never hands it out again.
    private(set) var fresh: (name: String, password: String)?

    func load(app: AppModel) async {
        errorMessage = nil
        do {
            passwords = try await app.client.appPasswords()
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func make(name: String, messages: Bool, app: AppModel) async {
        errorMessage = nil
        do {
            let password = try await app.client.createAppPassword(name: name, privileged: messages)
            fresh = (name, password)
            await load(app: app)
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revoke(_ password: AppPassword, app: AppModel) async {
        errorMessage = nil
        do {
            try await app.client.revokeAppPassword(name: password.name)
            passwords.removeAll { $0.name == password.name }
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }

    func forgetFresh() { fresh = nil }
}

struct AppPasswordsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model = AppPasswordsModel()
    @State private var name = ""
    @State private var allowsMessages = false
    @State private var pending: AppPassword?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.appPasswordsTitle),
                         onRefresh: { await model.load(app: app) }) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L(.appPasswordsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let fresh = model.fresh { justMade(fresh) }
                    if let error = model.errorMessage { failure(error) }

                    list
                    maker
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .task { await model.load(app: app) }
        .confirmationDialog(pending.map { L(.appPasswordRevokeAsk, $0.name) } ?? "",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button(L(.appPasswordRevoke), role: .destructive) {
                if let pending { Task { await model.revoke(pending, app: app) } }
                pending = nil
            }
            Button(L(.cancel), role: .cancel) { pending = nil }
        }
    }

    // MARK: - What is there

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: L(.appPasswordsTitle))

            if model.isLoading {
                ProgressView().controlSize(.small).tint(Theme.Palette.textTertiary)
            } else if model.passwords.isEmpty {
                Text(L(.appPasswordsEmpty))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                // The one thing the screen cannot know, said before the list
                // rather than after somebody has taken the wrong one back.
                Label(L(.appPasswordsWarning), systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(model.passwords) { password in
                    row(password)
                    Hairline()
                }
            }
        }
    }

    private func row(_ password: AppPassword) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(password.name)
                    .font(Theme.Font.ui(13, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 8) {
                    Text(L(.appPasswordCreated, RelativeTime.short(password.createdAt)))
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if password.canUseMessages {
                        Text(L(.appPasswordMessages))
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(L(.appPasswordRevoke)) { pending = password }
                .buttonStyle(.plain)
                .font(Theme.Font.ui(12))
                .foregroundStyle(Theme.Palette.danger)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Making one

    @ViewBuilder
    private var maker: some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: L(.appPasswordNew))

            MonoField(icon: "key", placeholder: L(.appPasswordNamePlaceholder), text: $name)

            Toggle(isOn: $allowsMessages) {
                Text(L(.appPasswordAllowMessages))
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            MonoButton(title: L(.appPasswordMake),
                       isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                let wanted = name.trimmingCharacters(in: .whitespaces)
                Task {
                    await model.make(name: wanted, messages: allowsMessages, app: app)
                    name = ""
                    allowsMessages = false
                }
            }
        }
    }

    /// The one moment the password itself exists outside the server.
    private func justMade(_ fresh: (name: String, password: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fresh.name)
                .font(Theme.Font.ui(12, .medium))
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(fresh.password)
                .font(Theme.Font.mono(15))
                .foregroundStyle(Theme.Palette.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button(copied ? L(.appPasswordCopied) : L(.appPasswordCopy)) {
                    copy(fresh.password)
                    copied = true
                }
                .buttonStyle(.plain)
                .font(Theme.Font.ui(12, .medium))
                .foregroundStyle(Theme.Palette.accent)

                Button(L(.close)) {
                    model.forgetFresh()
                    copied = false
                }
                .buttonStyle(.plain)
                .font(Theme.Font.ui(12))
                .foregroundStyle(Theme.Palette.textTertiary)
            }

            Text(L(.appPasswordOnce))
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Palette.surface)
        )
    }

    private func failure(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.Font.ui(13))
            .foregroundStyle(Theme.Palette.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
