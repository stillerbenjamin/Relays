//
//  MutedWordsView.swift
//  Relays
//
//  Words the account never wants to read. These live with the account, so they
//  hold in every client — unlike the feed rules, which stay on this device and
//  can do things the protocol has no room for.
//

import SwiftUI

struct MutedWordsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var targets: Set<MutedWord.Target> = [.content, .tag]
    @State private var scope: MutedWord.Scope = .all
    @State private var duration: Duration = .forever
    @State private var isSaving = false

    /// How long a word stays muted. Muting a word for the week a series runs is
    /// the case this exists for.
    enum Duration: String, CaseIterable, Identifiable {
        case forever, day, week, month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .forever: return L(.mutedWordForever)
            case .day: return L(.mutedWordDay)
            case .week: return L(.mutedWordWeek)
            case .month: return L(.mutedWordMonth)
            }
        }

        var expiry: Date? {
            switch self {
            case .forever: return nil
            case .day: return Date().addingTimeInterval(86_400)
            case .week: return Date().addingTimeInterval(7 * 86_400)
            case .month: return Date().addingTimeInterval(30 * 86_400)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.mutedWordsTitle)) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L(.mutedWordsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    composer
                    words
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
    }

    // MARK: - Adding one

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(L(.mutedWordPlaceholder), text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 12)
                .frame(height: Theme.Metric.fieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                        .fill(Theme.Palette.surface))

            HStack(spacing: 8) {
                ForEach(MutedWord.Target.allCases) { target in
                    Toggle(isOn: Binding(
                        get: { targets.contains(target) },
                        set: { on in
                            if on { targets.insert(target) } else { targets.remove(target) }
                            // One of the two has to stay on, or the word means nothing.
                            if targets.isEmpty { targets.insert(target) }
                        })) {
                            Text(target.label)
                        }
                        .toggleStyle(ChipToggleStyle())
                }
                Spacer(minLength: 0)
            }

            MonoSegment(selection: $scope, options: MutedWord.Scope.allCases, label: \.label)
            MonoSegment(selection: $duration, options: Duration.allCases, label: \.label)

            MonoButton(title: L(.mutedWordAdd), isLoading: isSaving) {
                Task { await add() }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }
        await app.addMutedWord(MutedWord(value: draft,
                                         targets: MutedWord.Target.allCases.filter(targets.contains),
                                         scope: scope,
                                         expiresAt: duration.expiry))
        draft = ""
        duration = .forever
    }

    // MARK: - What is muted

    @ViewBuilder
    private var words: some View {
        let list = app.mutedWords
        VStack(alignment: .leading, spacing: 0) {
            RelaySectionTitle(text: L(.mutedWordsTitle))
                .padding(.bottom, 10)

            if list.isEmpty {
                Text(L(.mutedWordsEmpty))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ForEach(list) { word in
                    MutedWordRow(word: word)
                    Hairline()
                }
            }
        }
    }
}

struct MutedWordRow: View {
    let word: MutedWord

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.value)
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(word.isExpired
                                     ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                    .strikethrough(word.isExpired)

                Text(summary)
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer(minLength: 8)

            Button { Task { await app.removeMutedWord(word) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(.mutedWordDelete))
        }
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = word.targets.map(\.label)
        if word.scope == .excludeFollowing { parts.append(word.scope.label) }
        if let expiresAt = word.expiresAt {
            parts.append(L(.mutedWordRemaining, RelativeTime.remaining(until: expiresAt)))
        }
        return parts.joined(separator: " · ")
    }
}

/// A small on/off chip, for settings that are a set rather than a choice.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(Theme.Font.ui(12, .medium))
                .foregroundStyle(configuration.isOn
                                 ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule().fill(configuration.isOn
                                   ? Theme.Palette.accent : Theme.Palette.surface))
        }
        .buttonStyle(.plain)
    }
}
