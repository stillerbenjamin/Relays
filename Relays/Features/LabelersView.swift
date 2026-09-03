//
//  LabelersView.swift
//  Relays
//
//  Choosing who moderates. Each service says which labels it applies and what it
//  means by them; the settings underneath decide what the app does about each
//  one. The list ends with what the server applies regardless — leaving that out
//  would suggest the choice is complete when it is not.
//

import SwiftUI

struct LabelersView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var results: [ActorProfile] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var directory: LabelerDirectory { app.labelers }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.labelersTitle)) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(L(.labelersHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    subscribed
                    search
                    applied
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .task { await directory.loadServices(client: app.client) }
    }

    // MARK: - Subscribed

    @ViewBuilder
    private var subscribed: some View {
        VStack(alignment: .leading, spacing: 14) {
            RelaySectionTitle(text: L(.labelersTitle))

            if directory.subscribed.isEmpty {
                Text(L(.labelersEmpty))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ForEach(directory.subscribed, id: \.self) { did in
                    if let service = directory.service(did) {
                        LabelerCard(service: service)
                    }
                }
            }
        }
    }

    // MARK: - Finding one

    private var search: some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: L(.labelersSearch))

            TextField(L(.labelersSearchHint), text: $term)
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
                .onChange(of: term) { _, value in schedule(value) }

            ForEach(results) { profile in
                LabelerResultRow(profile: profile)
            }

            if isSearching && results.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// Typing pauses before the network is asked; a search per keystroke would
    /// spend a rate limit on words nobody finished.
    private func schedule(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; return }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }

            let found = (try? await app.client.searchActors(term: trimmed, limit: 25).actors) ?? []
            guard !Task.isCancelled else { return }
            // Only accounts that actually run a service can be subscribed to.
            results = found.filter(\.isLabeler)
        }
    }

    // MARK: - What the server applies anyway

    @ViewBuilder
    private var applied: some View {
        let forced = app.appliedLabelers.filter { !directory.isSubscribed($0) }
        if !forced.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RelaySectionTitle(text: L(.labelersApplied))
                Text(L(.labelersAppliedHint))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(forced, id: \.self) { did in
                    Text(directory.service(did)?.name ?? did)
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// One subscribed service, with a setting for every value it publishes.
struct LabelerCard: View {
    let service: LabelerService
    var startsExpanded = false

    @Environment(AppModel.self) private var app
    @State private var isExpanded = false

    private var definitions: [LabelerService.Definition] {
        service.definitions
            .filter { LabelCatalog.definition(for: $0.identifier) == nil }
            .sorted { $0.localisedName < $1.localisedName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: Theme.Metric.avatarGap) {
                    AvatarView(url: service.creator.avatarURL,
                               seed: service.creator.handle, size: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.name)
                            .font(Theme.Font.ui(15, .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(L(.labelersValues, service.policies.labelValues.count))
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(.a11yServiceSettings))

            if isExpanded {
                Hairline()

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(definitions, id: \.identifier) { definition in
                        LabelSetting(definition: definition, labeler: service.did)
                    }

                    Button { Task { await app.unsubscribe(from: service.did) } } label: {
                        Text(L(.labelersUnsubscribe))
                            .font(Theme.Font.ui(13))
                            .foregroundStyle(Theme.Palette.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                .fill(Theme.Palette.surface))
        .onAppear { if startsExpanded { isExpanded = true } }
    }
}

/// One label of one service: what it means, and what to do about it.
struct LabelSetting: View {
    let definition: LabelerService.Definition
    let labeler: String

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(definition.localisedName)
                .font(Theme.Font.ui(13, .medium))
                .foregroundStyle(Theme.Palette.textPrimary)

            if let description = definition.localisedDescription {
                Text(description)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MonoSegment(selection: Binding(
                get: {
                    app.preferences.visibility(for: definition.identifier, from: labeler)
                        ?? definition.asDefinition.defaultSetting
                },
                set: { visibility in
                    Task {
                        await app.setVisibility(visibility, for: definition.identifier,
                                                from: labeler)
                    }
                }),
                        options: LabelVisibility.allCases,
                        label: \.label, fills: true)
        }
    }
}

/// A search hit that runs a service, with the one thing to do about it.
struct LabelerResultRow: View {
    let profile: ActorProfile

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: Theme.Metric.avatarGap) {
            AvatarView(url: profile.avatarURL, seed: profile.handle, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(Theme.Font.ui(14, .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("@\(profile.handle)")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            LabelerSubscribeButton(did: profile.did)
        }
        .padding(.vertical, 4)
    }
}

/// The one control that matters, wherever a labeler turns up.
struct LabelerSubscribeButton: View {
    let did: String

    @Environment(AppModel.self) private var app

    var body: some View {
        let subscribed = app.labelers.isSubscribed(did)

        Button {
            Task {
                if subscribed { await app.unsubscribe(from: did) }
                else { await app.subscribe(to: did) }
            }
        } label: {
            Text(subscribed ? L(.labelersUnsubscribe) : L(.labelersSubscribe))
                .font(Theme.Font.ui(12, .medium))
                .foregroundStyle(subscribed ? Theme.Palette.textSecondary : Theme.Palette.onAccent)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule().fill(subscribed ? Theme.Palette.surfaceRaised : Theme.Palette.accent))
        }
        .buttonStyle(.plain)
    }
}
