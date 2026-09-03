//
//  RepositoryView.swift
//  Relays
//
//  What the account's repository actually holds, and a way to take a copy of it.
//  Data ownership on the AT Protocol is an HTTP request; this makes it a button.
//

import SwiftUI

@MainActor
@Observable
final class RepositoryModel {

    struct CollectionCount: Identifiable, Hashable {
        let collection: String
        let count: Int
        let reachedCeiling: Bool

        var id: String { collection }
        /// `app.bsky.feed.post` reads as "post" in the list.
        var shortName: String { collection.split(separator: ".").last.map(String.init) ?? collection }
    }

    private(set) var counts: [CollectionCount] = []
    private(set) var isCounting = false
    private(set) var exportProgress: Double?
    private(set) var exportedFile: URL?
    private(set) var errorMessage: String?

    func loadCounts(app: AppModel) async {
        guard let did = app.session?.did, counts.isEmpty, !isCounting else { return }
        isCounting = true
        defer { isCounting = false }

        do {
            let collections = try await app.client.describeRepo(did: did)
            var results: [CollectionCount] = []
            for collection in collections {
                let result = try await app.client.countRecords(did: did, collection: collection)
                results.append(CollectionCount(collection: collection,
                                               count: result.count,
                                               reachedCeiling: result.reachedCeiling))
            }
            counts = results.sorted { $0.count > $1.count }
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }

    func export(app: AppModel) async {
        guard let did = app.session?.did, exportProgress == nil else { return }
        exportProgress = 0
        errorMessage = nil

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let file = try await app.client.exportRepo(did: did, to: directory) { [weak self] value in
                Task { @MainActor in self?.exportProgress = value }
            }
            exportedFile = file
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
        exportProgress = nil
    }
}

struct RepositoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model = RepositoryModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    exportSection
                    Hairline()

                    Text(L(.repoContents))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    Hairline()

                    if model.isCounting && model.counts.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if let error = model.errorMessage, model.counts.isEmpty {
                        StateMessage(text: error, systemImage: "exclamationmark.triangle")
                    } else {
                        ForEach(model.counts) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.shortName)
                                        .font(Theme.Font.body)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Text(entry.collection)
                                        .font(Theme.Font.mono(9))
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                }
                                Spacer()
                                Text(entry.reachedCeiling ? "\(entry.count)+" : "\(entry.count)")
                                    .font(Theme.Font.mono(14))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                            .padding(.horizontal, Theme.Metric.hPadding)
                            .frame(height: 52)
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
        .task { await model.loadCounts(app: app) }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.repoTitle))
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

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.repoExportHint))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let progress = model.exportProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(Theme.Palette.link)
                    Text("\(Int(progress * 100)) %")
                        .font(Theme.Font.ui(10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .contentTransition(.numericText())
                }
            } else if let file = model.exportedFile {
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.lastPathComponent)
                        .font(Theme.Font.ui(11))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ShareLink(item: file) {
                        Text(L(.repoShare))
                            .font(Theme.Font.ui(9))
                            .foregroundStyle(Theme.Palette.background)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.Palette.accent))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                MonoButton(title: L(.repoExport)) {
                    Task { await model.export(app: app) }
                }
            }

            if let error = model.errorMessage, model.exportedFile == nil {
                Text(error)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
        .padding(.vertical, 18)
    }
}
