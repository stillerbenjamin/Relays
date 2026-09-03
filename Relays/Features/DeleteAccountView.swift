//
//  DeleteAccountView.swift
//  Relays
//
//  An app that makes accounts has to be able to unmake them — Apple requires it,
//  and so does anyone who ever wants to leave. Two steps on purpose: the server
//  sends a code by email, and only that code together with the password removes
//  the account. Nothing here is reversible, and the screen says so more than once.
//

import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var token = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var showsConfirm = false
    @State private var errorMessage: String?

    private var canDelete: Bool { codeSent && !token.isEmpty && !password.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.deleteAccount)) {
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(L(.deleteAccountHint), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.Palette.danger.opacity(0.12)))

                    SettingsValueRow(label: L(.ruleHandle),
                                     value: app.session?.handle ?? "—")

                    Button {
                        Task { await requestCode() }
                    } label: {
                        Text(L(.deleteAccountRequest))
                            .font(Theme.Font.ui(14, .medium))
                            .foregroundStyle(Theme.Palette.link)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    if codeSent {
                        Text(L(.deleteAccountSent))
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.repost)
                    }

                    MonoField(icon: "number", placeholder: L(.deleteAccountCode), text: $token)
                    MonoField(icon: "key", placeholder: L(.authPassword), text: $password,
                              isSecure: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        showsConfirm = true
                    } label: {
                        Text(L(.deleteAccountConfirm))
                            .font(Theme.Font.ui(14, .medium))
                            .foregroundStyle(canDelete ? Theme.Palette.onAccent
                                                       : Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Metric.fieldHeight)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius,
                                                 style: .continuous)
                                    .fill(canDelete ? Theme.Palette.danger : Theme.Palette.surface))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete || isWorking)
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 22)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .relaysColorScheme()
        .confirmationDialog(L(.deleteAccountQuestion), isPresented: $showsConfirm,
                            titleVisibility: .visible) {
            Button(L(.deleteAccountConfirm), role: .destructive) {
                Task { await delete() }
            }
            Button(L(.cancel), role: .cancel) {}
        } message: {
            Text(L(.deleteAccountFinal))
        }
    }

    private func requestCode() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await app.requestAccountDeletion()
            codeSent = true
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await app.deleteAccount(password: password, token: token)
            dismiss()
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }
}
