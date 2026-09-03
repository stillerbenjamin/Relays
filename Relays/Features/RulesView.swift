//
//  RulesView.swift
//  Relays
//
//  Editor for the local feed rules. Nothing here leaves the device.
//

import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FeedRule.Kind = .keyword
    @State private var value = ""
    @State private var duration: RuleDuration = .forever

    private enum RuleDuration: String, CaseIterable, Identifiable {
        case forever, day, week

        var id: String { rawValue }
        var label: String {
            switch self {
            case .forever: return L(.ruleForever)
            case .day: return "24h"
            case .week: return "7d"
            }
        }
        var expiry: Date? {
            switch self {
            case .forever: return nil
            case .day: return Date().addingTimeInterval(86_400)
            case .week: return Date().addingTimeInterval(604_800)
            }
        }
    }

    private var canAdd: Bool {
        guard kind.needsValue else {
            return !app.rules.rules.contains { $0.kind == .selfHostedOnly }
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return kind != .regex || FeedRules.isValidRegex(trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    editor
                    Hairline()

                    if app.rules.rules.isEmpty {
                        StateMessage(text: L(.rulesEmpty), systemImage: "line.3.horizontal.decrease")
                    } else {
                        ForEach(app.rules.rules) { rule in
                            row(rule)
                            Hairline(inset: Theme.Metric.hPadding)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .relaysColorScheme()
        .onAppear { app.rules.pruneExpired() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.settingsRules))
                    .font(Theme.Font.ui(12, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.close)) { dismiss() }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 52)
            Hairline()
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(FeedRule.Kind.allCases) { option in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { kind = option }
                        } label: {
                            Text(option.label)
                                .font(Theme.Font.ui(9))
                                .foregroundStyle(kind == option ? Theme.Palette.background : Theme.Palette.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(kind == option ? Theme.Palette.accent : Theme.Palette.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)

            if kind.needsValue {
                MonoField(icon: kind == .regex ? "chevron.left.forwardslash.chevron.right" : "textformat",
                          placeholder: placeholder,
                          text: $value,
                          submitLabel: .done,
                          onSubmit: add)

                if kind == .regex, !value.isEmpty, !FeedRules.isValidRegex(value) {
                    Text(L(.ruleInvalidRegex))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.danger)
                }
            } else {
                Text(L(.ruleSelfHostedHint))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            HStack(spacing: 10) {
                ForEach(RuleDuration.allCases) { option in
                    Button {
                        duration = option
                    } label: {
                        Text(option.label)
                            .font(Theme.Font.ui(9))
                            .foregroundStyle(duration == option ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: add) {
                    Text(L(.ruleAdd))
                        .font(Theme.Font.ui(9))
                        .foregroundStyle(canAdd ? Theme.Palette.background : Theme.Palette.textTertiary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            Capsule().fill(canAdd ? Theme.Palette.accent : Theme.Palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 16)
    }

    private func row(_ rule: FeedRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.kind.label)
                    .font(Theme.Font.ui(8))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(rule.kind.needsValue ? rule.value : L(.ruleSelfHosted))
                    .font(Theme.Font.ui(12))
                    .foregroundStyle(rule.isActive ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                    .lineLimit(1)
                if let expiry = rule.expiresAt {
                    Text(L(.ruleUntil, RelativeTime.short(ATProtoClient.timestamp(expiry))))
                        .font(Theme.Font.ui(8))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer()

            MonoToggle(isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    app.rules.update(updated)
                }))

            Button {
                app.rules.remove(rule)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(.ruleDelete))
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .frame(minHeight: 54)
    }

    private var placeholder: String {
        switch kind {
        case .keyword: return L(.rulePlaceholderKeyword)
        case .regex: return L(.rulePlaceholderRegex)
        case .domain: return L(.rulePlaceholderDomain)
        case .handle: return L(.rulePlaceholderHandle)
        case .selfHostedOnly: return ""
        }
    }

    private func add() {
        guard canAdd else { return }
        app.rules.add(FeedRule(kind: kind,
                               value: value.trimmingCharacters(in: .whitespacesAndNewlines),
                               expiresAt: duration.expiry))
        value = ""
    }
}
