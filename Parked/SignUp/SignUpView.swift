//
//  SignUpView.swift
//  Relays
//
//  The form is built from what the server says it needs. An invite field appears
//  only where an invite is wanted, the phone step only where the server verifies
//  by text — so the same screen fits Bluesky's host and somebody's own server
//  without pretending both work the same way.
//

import SwiftUI

struct SignUpView: View {
    var onFinished: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draft = SignUpDraft()
    @State private var description: ServerDescription?
    @State private var handleState: HandleState = .unknown
    @State private var phoneSent = false
    @State private var isSubmitting = false
    @State private var isDescribing = false
    @State private var errorMessage: String?
    /// The server has asked for something this form cannot produce. Set only
    /// after it has actually refused — never guessed from the description.
    @State private var unsupported = false

    @State private var describeTask: Task<Void, Never>?
    @State private var handleTask: Task<Void, Never>?

    enum HandleState { case unknown, checking, free, taken }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.signUpTitle)) {
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    server
                    identity
                    if description?.needsInviteCode == true { invite }
                    if description?.needsPhone == true {
                        if draft.phoneVerificationRefused { phoneRefused } else { phone }
                    }
                    terms

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.ui(13))
                            .foregroundStyle(Theme.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if unsupported { wayOut }

                    MonoButton(title: L(.signUpCreate), isLoading: isSubmitting,
                               isEnabled: draft.isComplete(for: description), action: submit)
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 22)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .relaysColorScheme()
        .task { await describe() }
    }

    // MARK: - Server

    private var server: some View {
        VStack(alignment: .leading, spacing: 8) {
            RelaySectionTitle(text: L(.signUpServer))

            MonoField(icon: "server.rack", placeholder: ServerDescription.defaultHost,
                      text: $draft.host)
                .onChange(of: draft.host) { _, _ in scheduleDescribe() }

            HStack(spacing: 6) {
                if isDescribing { ProgressView().controlSize(.mini) }
                Text(L(.signUpServerHint))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Who one will be

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoField(icon: "at", placeholder: L(.signUpHandle), text: $draft.handle)
                .onChange(of: draft.handle) { _, _ in scheduleHandleCheck() }

            HStack(spacing: 6) {
                // The full handle, so nobody is surprised by the suffix later.
                Text(draft.fullHandle(on: description))
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                switch handleState {
                case .checking: ProgressView().controlSize(.mini)
                case .free:
                    Text(L(.signUpHandleFree))
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.repost)
                case .taken:
                    Text(L(.signUpHandleTaken))
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.danger)
                case .unknown:
                    EmptyView()
                }
                Spacer(minLength: 0)
            }

            MonoField(icon: "envelope", placeholder: L(.signUpEmail), text: $draft.email)

            MonoField(icon: "key", placeholder: L(.signUpPassword), text: $draft.password,
                      isSecure: true)

            Text(L(.signUpPasswordHint))
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            #if os(macOS)
            // The compact picker draws a white stepper field, which reads as a
            // hole in a themed sheet. This is the app's own field with the
            // calendar behind it.
            AppDateField(title: L(.signUpBirthDate), date: $draft.birthDate)
            #else
            DatePicker(L(.signUpBirthDate), selection: $draft.birthDate,
                       in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(Theme.Font.ui(14))
                .foregroundStyle(Theme.Palette.textPrimary)
                .tint(Theme.Palette.accent)
            #endif

            if !draft.isOldEnough {
                Text(L(.signUpTooYoung))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
    }

    // MARK: - What this server wants on top

    private var invite: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoField(icon: "ticket", placeholder: L(.signUpInvite), text: $draft.inviteCode)
            Text(L(.signUpInviteHint))
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    /// The server asked for a number and then would not send a code to it.
    /// Saying so beats leaving a field nobody can fill.
    private var phoneRefused: some View {
        Text(L(.signUpPhoneOff))
            .font(Theme.Font.micro)
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var phone: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The server has to send a real message to this number, so it needs
            // the country in front of it. Nobody types their own country code.
            DiallingCodeField(region: $draft.phoneRegion,
                              number: $draft.phone,
                              placeholder: L(.signUpPhone))

            if !draft.phone.isEmpty {
                Text(draft.phoneE164)
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(draft.phoneLooksLikeOne ? Theme.Palette.textSecondary
                                                             : Theme.Palette.textTertiary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await sendPhoneCode() }
                } label: {
                    Text(L(.signUpPhoneSend))
                        .font(Theme.Font.ui(12, .medium))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
                .disabled(!draft.phoneLooksLikeOne)

                if phoneSent {
                    Text(L(.signUpPhoneSent))
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.repost)
                }
                Spacer(minLength: 0)
            }

            MonoField(icon: "number", placeholder: L(.signUpPhoneCode), text: $draft.phoneCode)

            Text(L(.signUpPhoneHint))
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The way out

    /// When a server refuses an account for something the form cannot supply,
    /// a fifth attempt at the same form is not an answer. Its own sign-up page
    /// is.
    @ViewBuilder
    private var wayOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(.signUpUnsupported))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = signUpURL {
                Button(L(.signUpOpenInBrowser)) { openURL(url) }
                    .buttonStyle(.plain)
                    .font(Theme.Font.ui(13, .medium))
                    .foregroundStyle(Theme.Palette.link)
            }
        }
    }

    /// The server the person chose, not Bluesky's — the same rule the terms
    /// links follow.
    private var signUpURL: URL? {
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        return URL(string: host.contains("://") ? host : "https://\(host)")
    }

    // MARK: - Terms

    private var terms: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $draft.acceptedTerms) {
                Text(L(.signUpTerms))
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)

            // The server's own documents, not Bluesky's — this form is not only
            // used against Bluesky.
            HStack(spacing: 14) {
                if let url = description?.termsURL {
                    Button(L(.signUpTermsLink)) { openURL(url) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.link)
                }
                if let url = description?.privacyPolicyURL {
                    Button(L(.signUpPrivacyLink)) { openURL(url) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.link)
                }
                Spacer(minLength: 0)
            }
            .font(Theme.Font.ui(12))
        }
    }

    // MARK: - Work

    /// Typing a host should not describe it on every keystroke.
    private func scheduleDescribe() {
        describeTask?.cancel()
        describeTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await describe()
        }
    }

    private func describe() async {
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        isDescribing = true
        defer { isDescribing = false }

        do {
            description = try await ATProtoClient.describeServer(host: host)
            errorMessage = nil
            unsupported = false
        } catch {
            description = nil
            errorMessage = L(.signUpServerFailed)
        }
        scheduleHandleCheck()
    }

    private func scheduleHandleCheck() {
        handleTask?.cancel()
        let full = draft.fullHandle(on: description)
        guard full.contains("."), full.count > 4 else { handleState = .unknown; return }

        handleTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            handleState = .checking
            let free = await ATProtoClient.isHandleFree(full, host: draft.host)
            guard !Task.isCancelled else { return }
            handleState = free ? .free : .taken
        }
    }

    private func sendPhoneCode() async {
        errorMessage = nil
        do {
            try await app.client.requestPhoneVerification(phone: draft.phoneE164)
            phoneSent = true
        } catch {
            let text = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            // bsky.social answers `phoneVerificationRequired: true` in its own
            // description and then refuses every request for a code. Verified
            // against the live server. Taking the server at its second word is
            // the only way past a form it made impossible to finish.
            if text.localizedCaseInsensitiveContains("phone verification not enabled") {
                draft.phoneVerificationRefused = true
                phoneSent = false
            } else {
                errorMessage = text
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        unsupported = false

        Task {
            do {
                try await app.signUp(draft: draft, description: description)
                onFinished?()
                dismiss()
            } catch {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
                // A server that asked for a phone number, refused to send a code
                // to it, and has now refused the account is asking for something
                // this form cannot produce. `bsky.social` does exactly that.
                unsupported = draft.phoneVerificationRefused
            }
            isSubmitting = false
        }
    }
}
