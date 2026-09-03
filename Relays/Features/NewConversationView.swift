//
//  NewConversationView.swift
//  Relays
//
//  Starting a conversation: find the person, and the service hands back the
//  conversation with them — existing or new, it makes no difference here.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class NewConversationModel {
    private(set) var results: [ActorProfile] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    /// Set once a conversation is ready to be opened.
    private(set) var startedConvo: String?

    private var task: Task<Void, Never>?

    func search(term: String, app: AppModel) {
        task?.cancel()
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            results = []
            return
        }

        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = (try? await app.client.typeahead(term: query, limit: 12)) ?? []
            isSearching = false
        }
    }

    func start(with profile: ActorProfile, app: AppModel) async {
        errorMessage = nil
        do {
            startedConvo = try await app.client.conversation(with: profile.did).id
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct NewConversationView: View {
    var onStart: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model = NewConversationModel()
    @State private var term = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            MonoField(icon: "magnifyingglass",
                      placeholder: L(.newMessageSearch),
                      text: $term,
                      submitLabel: .search)
                .padding(.horizontal, Theme.Metric.hPadding)
                .padding(.vertical, 12)

            if let error = model.errorMessage {
                Text(error)
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metric.hPadding)
                    .padding(.bottom, 8)
            }

            if model.results.isEmpty {
                StateMessage(text: term.count >= 2 ? L(.searchEmpty) : L(.newMessageHint),
                             systemImage: "person.2")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { profile in
                            Button {
                                Task { await model.start(with: profile, app: app) }
                            } label: {
                                ActorRow(profile: profile)
                            }
                            .buttonStyle(.plain)
                            Hairline(inset: Theme.Metric.hPadding)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .relaysBackground()
        .relaysColorScheme()
        .onChange(of: term) { _, new in model.search(term: new, app: app) }
        .onChange(of: model.startedConvo) { _, id in
            guard let id else { return }
            dismiss()
            onStart(id)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.newMessage))
                    .font(Theme.Font.ui(17, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 56)
            Hairline()
        }
    }
}
