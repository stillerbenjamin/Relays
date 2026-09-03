//
//  SettingsView.swift
//  Relays
//

import SwiftUI

/// The settings, presented from the gear in one's own profile.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.titleSettings))
                    .font(Theme.Font.ui(17, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.close)) { dismiss() }
                    .font(Theme.Font.ui(15, .medium))
                    .foregroundStyle(Theme.Palette.link)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 56)
            Hairline()

            ScrollView {
                SettingsSections()
                    .padding(.bottom, 32)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .relaysColorScheme()
    }
}

/// The options themselves, so they can also be shown inline elsewhere.
struct SettingsSections: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications

    @State private var showsSignOutConfirm = false
    @State private var showsRules = false
    @State private var showsRepository = false
    @State private var showsLabelers = false
    @State private var showsMutedWords = false
    @State private var showsNotifyKinds = false
    @State private var showsLists = false
    @State private var showsDeleteAccount = false
    @State private var showsAddAccount = false

    var body: some View {
        @Bindable var settings = settings

        return VStack(spacing: 0) {
            section(L(.settingsAppearance)) {
                SettingsRow(label: L(.settingsTheme), stacked: true) {
                    MonoSegment(selection: $settings.theme,
                                options: AppTheme.allCases,
                                label: \.label, fills: true)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsLanguage), stacked: true) {
                    MonoSegment(selection: $settings.language,
                                options: AppLanguage.allCases,
                                label: \.label, fills: true)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsTextSize), stacked: true) {
                    MonoSegment(selection: $settings.textSize,
                                options: TextSizeOption.allCases,
                                label: \.label, fills: true)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsSlimFonts)) {
                    MonoToggle(isOn: $settings.slimFonts)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsDynamicType)) {
                    MonoToggle(isOn: $settings.followDynamicType)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsCompact)) {
                    MonoToggle(isOn: $settings.compactMode)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsShowImages)) {
                    MonoToggle(isOn: $settings.showImages)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsAltBadge)) {
                    MonoToggle(isOn: $settings.showAltBadge)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsCounts)) {
                    MonoToggle(isOn: $settings.showCounts)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsShowOrigin)) {
                    MonoToggle(isOn: $settings.showPDSOrigin)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsAbsoluteTime)) {
                    MonoToggle(isOn: $settings.absoluteTime)
                }
            }

            section(L(.settingsFeed)) {
                SettingsRow(label: L(.settingsHideReposts)) {
                    MonoToggle(isOn: $settings.hideReposts)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsHideReplies)) {
                    MonoToggle(isOn: $settings.hideReplies)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsAutoRefresh)) {
                    MonoToggle(isOn: $settings.autoRefresh)
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.relayPulse), detail: L(.relayPulseHint)) {
                    MonoToggle(isOn: $settings.relayPulse)
                }
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.settingsRules), detail: L(.rulesActive, app.rules.activeCount)) {
                    showsRules = true
                }

            }

            section(L(.settingsModeration)) {
                SettingsRow(label: L(.moderationAdult), detail: L(.moderationAdultHint)) {
                    MonoToggle(isOn: Binding(get: { app.preferences.adultContentEnabled },
                                             set: { value in
                                                 Task { await app.setAdultContent(value) }
                                             }))
                }
                Hairline(inset: Theme.Metric.hPadding)

                SettingsRow(label: L(.moderationLabels), detail: L(.moderationLabelsHint)) {
                    EmptyView()
                }
                Hairline(inset: Theme.Metric.hPadding)

                ForEach(LabelCatalog.adjustable, id: \.self) { value in
                    let definition = LabelCatalog.definition(for: value)
                    SettingsRow(label: definition?.title ?? value, stacked: true) {
                        MonoSegment(selection: Binding(
                            get: {
                                app.preferences.visibility(for: value, from: nil)
                                    ?? definition?.defaultSetting ?? .warn
                            },
                            set: { visibility in
                                Task { await app.setVisibility(visibility, for: value) }
                            }),
                                    options: LabelVisibility.allCases,
                                    label: \.label, fills: true)
                    }
                    Hairline(inset: Theme.Metric.hPadding)
                }

                SettingsRow(label: L(.messagesWho), stacked: true) {
                    MonoSegment(selection: Binding(get: { app.messageRule },
                                                   set: { rule in
                                                       Task { await app.setMessageRule(rule) }
                                                   }),
                                options: MessageRule.allCases,
                                label: \.label,
                                fills: true)
                }
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.mutedWordsOpen),
                           detail: L(.rulesActive, app.mutedWords.count)) {
                    showsMutedWords = true
                }
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.listsOpen)) { showsLists = true }
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.labelersOpen),
                           detail: L(.labelersValues, app.labelers.subscribed.count)) {
                    showsLabelers = true
                }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsValueRow(label: L(.moderationAccounts),
                                 value: "\(L(.moderationMutedCount, app.mutedActors.count)) · "
                                      + "\(L(.moderationBlockedCount, app.blockedActors.count))")
            }

            section(L(.settingsNotifications)) {
                SettingsRow(label: L(.notifyEnabled)) {
                    MonoToggle(isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { wanted in
                            // The system prompt belongs here, where the intent is clear.
                            Task {
                                if wanted, notifications.permission != .granted {
                                    settings.notificationsEnabled = await notifications.requestPermission()
                                } else {
                                    settings.notificationsEnabled = wanted
                                }
                                BackgroundRefresh.schedule(settings: settings)
                            }
                        }))
                }

                if notifications.permission == .denied {
                    Hairline(inset: Theme.Metric.hPadding)
                    Text(L(.notifyDenied))
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .padding(.vertical, 10)
                }

                // Outside the master switch on purpose: what appears in the
                // notifications list is a setting that applies whether or not
                // this device is allowed to interrupt anybody.
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.notifyKinds), detail: activeKinds) { showsNotifyKinds = true }

                if settings.notificationsEnabled {
                    Hairline(inset: Theme.Metric.hPadding)
                    Text(L(.notifyHint))
                        .font(Theme.Font.ui(13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .padding(.vertical, 10)
                }
            }

            section(L(.settingsBehavior)) {
                SettingsRow(label: L(.settingsOpenInApp)) {
                    MonoToggle(isOn: $settings.openLinksInApp)
                }
                #if os(iOS)
                Hairline(inset: Theme.Metric.hPadding)
                SettingsRow(label: L(.settingsHaptics)) {
                    MonoToggle(isOn: $settings.haptics)
                }
                #endif
            }

            section(L(.accountsTitle)) {
                ForEach(app.accounts, id: \.session.did) { stored in
                    Button {
                        Task { await app.switchTo(did: stored.session.did) }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(stored.session.did == app.session?.did ? Theme.Palette.link : Theme.Palette.surfaceRaised)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(stored.session.handle)")
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text(stored.service.replacingOccurrences(of: "https://", with: ""))
                                    .font(Theme.Font.mono(9))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer()
                            if stored.session.did != app.session?.did {
                                Text(L(.accountSwitch))
                                    .font(Theme.Font.ui(8))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline(inset: Theme.Metric.hPadding)
                }

                disclosure(L(.accountAdd), icon: "plus") { showsAddAccount = true }
                Hairline(inset: Theme.Metric.hPadding)
                SettingsValueRow(label: L(.settingsDID), value: app.session?.did ?? "—", truncatesMiddle: true)
                Hairline(inset: Theme.Metric.hPadding)
                SettingsValueRow(label: L(.settingsServer),
                                 value: (app.session?.service ?? ATProtoClient.defaultService)
                                    .replacingOccurrences(of: "https://", with: ""))
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.repoTitle)) { showsRepository = true }
                Hairline(inset: Theme.Metric.hPadding)
                disclosure(L(.deleteAccount)) { showsDeleteAccount = true }
                Hairline(inset: Theme.Metric.hPadding)

                Button { showsSignOutConfirm = true } label: {
                    HStack {
                        Text(L(.signOut))
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.danger)
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.danger)
                    }
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.signOut))
            }

            section(L(.settingsAbout)) {
                SettingsValueRow(label: L(.settingsTypeface),
                                 value: Theme.Font.hasInter ? "Inter" : L(.settingsSystemFace))
                Hairline(inset: Theme.Metric.hPadding)
                SettingsValueRow(label: L(.settingsVersion), value: Self.version)
                Hairline(inset: Theme.Metric.hPadding)
                SettingsValueRow(label: L(.settingsProtocol), value: "AT Protocol")
            }

            Wordmark(size: 13)
                .opacity(0.25)
                .padding(.vertical, 32)
        }
        .sheet(isPresented: $showsNotifyKinds) {
            NotificationKindsView()
                .presentationBackground(Theme.Palette.background)
                .sheetSize()
        }
        .sheet(isPresented: $showsRules) {
            RulesView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsMutedWords) {
            MutedWordsView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsLists) {
            ListsView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsLabelers) {
            LabelersView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsDeleteAccount) {
            DeleteAccountView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsRepository) {
            RepositoryView()
                .presentationBackground(Theme.Palette.background)
        }
        .sheet(isPresented: $showsAddAccount) {
            AddAccountView()
                .presentationBackground(Theme.Palette.background)
        }
        .confirmationDialog(L(.signOutQuestion), isPresented: $showsSignOutConfirm, titleVisibility: .visible) {
            Button(L(.signOut), role: .destructive) {
                Task { await app.signOut() }
            }
            Button(L(.cancel), role: .cancel) {}
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// A row that opens something else.
    /// How many kinds still alert. A number rather than a list, the way the
    /// rules and muted-words rows read.
    private var activeKinds: String {
        let on = NotificationPreferences.Kind.allCases
            .filter { app.notificationPreferences[$0].push }.count
        return "\(on)/\(NotificationPreferences.Kind.allCases.count)"
    }

    private func disclosure(_ label: String, detail: String? = nil,
                            icon: String = "chevron.right",
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Font.ui(13, .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.top, 26)
                .padding(.bottom, 8)

            Hairline()
            content()
            Hairline()
        }
    }
}

// MARK: - Building blocks

struct SettingsRow<Trailing: View>: View {
    let label: String
    /// A second line under the label, for settings that cost something.
    var detail: String? = nil
    /// Puts the control on its own line. For choices whose wordings are too long
    /// to sit beside their label — beside it they wrap or get cut, and at every
    /// text size, not only the large ones.
    var stacked = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 10) {
                    caption
                    trailing
                }
                .padding(.vertical, 12)
            } else {
                HStack(spacing: 12) {
                    caption
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .frame(minHeight: 46)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsValueRow: View {
    let label: String
    let value: String
    var truncatesMiddle: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(truncatesMiddle ? .middle : .tail)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .frame(height: 46)
    }
}

/// Segmented picker in the monospaced style: active option white, inactive grey.
struct MonoSegment<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    /// Spreads the options over the full width instead of sizing them to their
    /// text. For long wordings this is the difference between a row and a mess.
    var fills = false

    init(selection: Binding<Option>, options: [Option], label: KeyPath<Option, String>,
         fills: Bool = false) {
        self._selection = selection
        self.options = options
        self.label = { $0[keyPath: label] }
        self.fills = fills
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(Theme.Font.micro)
                        .lineLimit(1)
                        // Only the last resort: the row is meant to be wide
                        // enough, and shrinking is what happens when it is not.
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selection == option ? Theme.Palette.background : Theme.Palette.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: fills ? .infinity : nil)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option ? Theme.Palette.accent : Theme.Palette.surface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: fills ? .infinity : nil)
    }
}

/// A switch in the app's own style instead of the system toggle.
struct MonoToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Palette.accent : Theme.Palette.surface)
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(isOn ? Theme.Palette.background : Theme.Palette.textTertiary)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
    }
}
