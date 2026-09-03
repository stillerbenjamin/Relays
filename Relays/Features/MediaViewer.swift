//
//  MediaViewer.swift
//  Relays
//
//  Full-screen image viewing with pinch zoom, and HLS playback for video embeds.
//

import SwiftUI
import AVKit

struct ImageViewer: View {
    let images: [EmbedImage]
    @State var index: Int
    /// Set when the viewer is an overlay rather than a presented sheet. There is
    /// nothing for `dismiss` to dismiss in that case, and it silently does
    /// nothing — which reads as a close button that does not work.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private var current: EmbedImage? {
        images.indices.contains(index) ? images[index] : images.first
    }

    var body: some View {
        ZStack {
            backdrop
            pager
            controls
        }
        .onChange(of: index) { _, _ in resetZoom() }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var backdrop: some View {
        #if os(iOS)
        Color.black.ignoresSafeArea()
        #else
        Color.black
        #endif
    }

    @ViewBuilder
    private var pager: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(Array(images.enumerated()), id: \.offset) { position, image in
                picture(image, at: position).tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
        #else
        // On macOS a plain TabView is a row of tab buttons, and an integer tag
        // with no label draws an empty white pill over the picture. One picture
        // at a time here, with arrows and the arrow keys to move between them.
        if let current {
            picture(current, at: index)
        }
        #endif
    }

    private func picture(_ image: EmbedImage, at position: Int) -> some View {
        AsyncImage(url: image.fullsizeURL ?? image.thumbURL) { phase in
            switch phase {
            case .success(let rendered):
                rendered
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(position == index ? zoom : 1)
                    .offset(position == index ? offset : .zero)
                    .gesture(magnification)
                    .simultaneousGesture(drag)
                    .onTapGesture(count: 2) { toggleZoom() }
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.Palette.onMedia.opacity(0.5))
            default:
                ProgressView().tint(Theme.Palette.onMedia.opacity(0.6))
            }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                #if os(macOS)
                if images.count > 1 {
                    Text(L(.imageCount, String(index + 1), String(images.count)))
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(Theme.Palette.onMedia.opacity(0.7))
                }
                #endif
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.onMedia)
                        .padding(10)
                        .background(Circle().fill(Theme.Palette.mediaScrim))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.close))
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif
            }

            Spacer()

            if let alt = current?.alt, !alt.isEmpty {
                Text(alt)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.onMedia.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.6))
                    )
            }
        }
        .padding(18)
        #if os(macOS)
        .overlay { arrows }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var arrows: some View {
        if images.count > 1 {
            HStack {
                arrow(-1, "chevron.left", L(.imagePrevious))
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                arrow(1, "chevron.right", L(.imageNext))
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(.horizontal, 4)
        }
    }

    private func arrow(_ by: Int, _ symbol: String, _ label: String) -> some View {
        Button { step(by) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.onMedia)
                .padding(12)
                .background(Circle().fill(Theme.Palette.mediaScrim))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
    #endif

    /// Wraps, so the last picture and the first are neighbours in both
    /// directions rather than dead ends.
    private func step(_ by: Int) {
        guard images.count > 1 else { return }
        index = (index + by + images.count) % images.count
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(6, max(1, committedZoom * value.magnification)) }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1.02 { resetZoom() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if zoom > 1 { resetZoom() } else { zoom = 2.5; committedZoom = 2.5 }
        }
    }

    private func resetZoom() {
        zoom = 1; committedZoom = 1
        offset = .zero; committedOffset = .zero
    }
}

/// Video embeds: thumbnail with a play control, playback in a sheet.
struct VideoCard: View {
    let video: EmbedVideo

    @Environment(AppSettings.self) private var settings
    @State private var isPlaying = false

    private var ratio: CGFloat {
        guard let aspect = video.aspectRatio, aspect.height > 0 else { return 16.0 / 9.0 }
        return CGFloat(aspect.width) / CGFloat(aspect.height)
    }

    var body: some View {
        Button {
            isPlaying = true
        } label: {
            ZStack {
                if settings.showImages, let thumbnailURL = video.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Theme.Palette.surface
                        }
                    }
                } else {
                    Theme.Palette.surface
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.onMedia)
                    .padding(14)
                    .background(Circle().fill(Theme.Palette.mediaScrim))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(max(0.6, min(ratio, 1.9)), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if settings.showAltBadge, let alt = video.alt, !alt.isEmpty {
                    Text("ALT")
                        .font(Theme.Font.ui(8, .medium))
                        .tracking(0.4)
                        .foregroundStyle(Theme.Palette.onMedia)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel(video.alt ?? L(.video))
        .sheet(isPresented: $isPlaying) {
            VideoSheet(url: video.playlistURL)
                .presentationBackground(.black)
        }
    }
}

private struct VideoSheet: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            } else {
                StateMessage(text: L(.videoUnavailable), systemImage: "play.slash")
            }
        }
    }
}
