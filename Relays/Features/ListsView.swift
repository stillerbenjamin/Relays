//
//  ListsView.swift
//  Relays
//
//  Lists handle many accounts at once. Subscribing to somebody else's list is
//  the fastest moderation there is — and the most worth looking at first, which
//  is why a list here opens to show who is actually on it.
//

import SwiftUI

struct ListsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L(.listsTitle)) {
                Button { dismiss() } label: {
                    Text(L(.close))
                        .font(Theme.Font.ui(14))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(L(.listsHint))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    subscribed
                    mine
                }
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .task { await app.loadLists() }
    }

    @ViewBuilder
    private var subscribed: some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: L(.listsSubscribed))

            if app.subscribedLists.isEmpty {
                Text(L(.listsEmpty))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ForEach(app.subscribedLists) { list in
                    ListCard(list: list)
                }
            }
        }
    }

    @ViewBuilder
    private var mine: some View {
        VStack(alignment: .leading, spacing: 12) {
            RelaySectionTitle(text: L(.listsMine))

            ForEach(app.ownLists) { list in
                ListCard(list: list)
            }

            HStack(spacing: 8) {
                TextField(L(.listNamePlaceholder), text: $newName)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.Metric.fieldHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                            .fill(Theme.Palette.surface))

                Button {
                    Task {
                        isCreating = true
                        await app.createList(named: newName)
                        newName = ""
                        isCreating = false
                    }
                } label: {
                    Text(L(.listCreate))
                        .font(Theme.Font.ui(13, .medium))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: Theme.Metric.fieldHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius,
                                             style: .continuous)
                                .fill(Theme.Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || isCreating)
            }
        }
    }
}

/// One list: what it is, who is on it, and the two things one can do about it.
struct ListCard: View {
    let list: ListView

    @Environment(AppModel.self) private var app
    @State private var members: [ActorProfile] = []
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: Theme.Metric.avatarGap) {
                    AvatarView(url: list.avatarURL, seed: list.uri, size: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(list.name)
                            .font(Theme.Font.ui(15, .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(L(.listMembers, list.listItemCount ?? 0))
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
            .accessibilityLabel(list.name)

            if isExpanded {
                Hairline()

                VStack(alignment: .leading, spacing: 12) {
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Who is on a list decides whether it is worth subscribing to.
                    ForEach(members.prefix(8)) { member in
                        HStack(spacing: 8) {
                            AvatarView(url: member.avatarURL, seed: member.handle, size: 22)
                            Text("@\(member.handle)")
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }

                    if list.isModeration {
                        HStack(spacing: 10) {
                            Button { Task { await app.toggleListMute(list) } } label: {
                                pill(app.isListMuted(list.uri) ? L(.listUnmute) : L(.listMute),
                                     active: app.isListMuted(list.uri))
                            }
                            .buttonStyle(.plain)

                            Button { Task { await app.toggleListBlock(list) } } label: {
                                pill(list.viewer?.blocked != nil ? L(.listUnblock) : L(.listBlock),
                                     active: list.viewer?.blocked != nil)
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .task(id: isExpanded) {
                    guard isExpanded, members.isEmpty else { return }
                    members = (try? await app.client.list(uri: list.uri, limit: 12).items
                        .map(\.subject)) ?? []
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                .fill(Theme.Palette.surface))
    }

    private func pill(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(Theme.Font.ui(12, .medium))
            .foregroundStyle(active ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(active ? Theme.Palette.accent : Theme.Palette.surfaceRaised))
    }
}
