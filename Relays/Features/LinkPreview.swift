//
//  LinkPreview.swift
//  Relays
//
//  Preview card for external links (app.bsky.embed.external) plus the in-app browser.
//

import SwiftUI
#if canImport(SafariServices) && os(iOS)
import SafariServices
import UIKit
#endif

struct LinkPreviewCard: View {
    let external: EmbedExternal

    @Environment(AppSettings.self) private var settings
    @Environment(\.openLink) private var openLink

    private var thumbURL: URL? {
        guard settings.showImages, let thumb = external.thumb else { return nil }
        return URL(string: thumb)
    }

    var body: some View {
        Button {
            if let url = external.url { openLink(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let thumbURL {
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            thumbFallback
                        default:
                            Theme.Palette.surfaceRaised
                        }
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) { Hairline() }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                        Text(external.host)
                            .font(Theme.Font.micro)
                            .tracking(0.4)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Palette.link)

                    if let title = external.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        Text(title)
                            .font(Theme.Font.ui(13, .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    if let description = external.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        Text(description)
                            .font(Theme.Font.micro)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel(external.title ?? external.host)
    }

    /// With no loadable image the domain carries the card.
    private var thumbFallback: some View {
        ZStack {
            Theme.Palette.surfaceRaised
            Text(external.host.uppercased())
                .font(Theme.Font.ui(11))
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}

// MARK: - Opening links

/// Opens links in the embedded browser (iOS) or the system browser.
struct OpenLinkAction {
    let handler: (URL) -> Void
    func callAsFunction(_ url: URL) { handler(url) }
    init(_ handler: @escaping (URL) -> Void) { self.handler = handler }
}

private struct OpenLinkKey: EnvironmentKey {
    static let defaultValue = OpenLinkAction { url in
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

extension EnvironmentValues {
    var openLink: OpenLinkAction {
        get { self[OpenLinkKey.self] }
        set { self[OpenLinkKey.self] = newValue }
    }
}

#if os(iOS)
/// SFSafariViewController as a sheet — keeps reader mode and cookie isolation.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = .white
        controller.preferredBarTintColor = .black
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

/// Attaches the in-app browser to a view and provides `openLink`.
struct InAppBrowserModifier: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @State private var link: IdentifiableURL?

    func body(content: Content) -> some View {
        content
            .environment(\.openLink, OpenLinkAction { url in
                #if os(iOS)
                if settings.openLinksInApp {
                    link = IdentifiableURL(url: url)
                } else {
                    UIApplication.shared.open(url)
                }
                #else
                NSWorkspace.shared.open(url)
                #endif
            })
            #if os(iOS)
            .sheet(item: $link) { item in
                SafariSheet(url: item.url)
                    .ignoresSafeArea()
            }
            #endif
    }

    private struct IdentifiableURL: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
}

extension View {
    func withInAppBrowser() -> some View { modifier(InAppBrowserModifier()) }
}
