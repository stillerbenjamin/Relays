//
//  RecordInspectorView.swift
//  Relays
//
//  "View source" for a post: the AT URI, the CID, where the account lives and the
//  raw lexicon record the network actually stores.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct RecordInspectorView: View {
    let post: PostView

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var json: String?
    @State private var errorMessage: String?
    @State private var copied: String?

    private var origin: AccountOrigin? { app.directory.origin(for: post.author.did) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field(L(.inspectorAuthor), "@\(post.author.handle)")
                    field(L(.inspectorDID), post.author.did)
                    field(L(.inspectorPDS), origin?.host ?? "…")
                    field(L(.inspectorURI), post.uri)
                    field(L(.inspectorCID), post.cid)
                    field(L(.inspectorCreated), post.record.createdAt ?? "—")
                    field(L(.inspectorIndexed), post.indexedAt)
                    if let facets = post.record.facets, !facets.isEmpty {
                        field(L(.inspectorFacets), facetSummary(facets))
                    }

                    Text(L(.inspectorRecord))
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Metric.hPadding)
                        .padding(.top, 26)
                        .padding(.bottom, 10)

                    Hairline()

                    Group {
                        if let json {
                            Text(json)
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Metric.hPadding)
                        } else if let errorMessage {
                            StateMessage(text: errorMessage, systemImage: "exclamationmark.triangle")
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.Palette.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.never)
        }
        .relaysBackground()
        .relaysColorScheme()
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(.inspectorTitle))
                    .font(Theme.Font.mono(12, .medium))
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

    /// One labelled value; tapping copies it, which is the point of this screen.
    private func field(_ label: String, _ value: String) -> some View {
        Button {
            copy(value)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(Theme.Font.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if copied == value {
                        Text(L(.copied))
                            .font(Theme.Font.mono(8))
                            .foregroundStyle(Theme.Palette.link)
                    }
                    Spacer()
                }
                Text(value)
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metric.hPadding)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline(inset: Theme.Metric.hPadding) }
    }

    private func facetSummary(_ facets: [Facet]) -> String {
        facets.map { facet in
            let kind: String
            switch facet.features.first {
            case .link: kind = "link"
            case .mention: kind = "mention"
            case .tag: kind = "tag"
            default: kind = "unknown"
            }
            return "\(kind) [\(facet.index.byteStart)…\(facet.index.byteEnd)]"
        }.joined(separator: "\n")
    }

    private func load() async {
        app.directory.resolve(post.author.did)
        do {
            json = try await app.client.rawRecord(uri: post.uri)
        } catch {
            errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        withAnimation(.easeOut(duration: 0.15)) { copied = value }
    }
}
