//
//  Overlays.swift
//  Relays
//
//  Full-screen presentations that any row can trigger: the image viewer and the
//  record inspector. Both travel through the environment so posts stay decoupled.
//

import SwiftUI

struct OpenImagesAction {
    let handler: ([EmbedImage], Int) -> Void
    func callAsFunction(_ images: [EmbedImage], at index: Int = 0) { handler(images, index) }
    init(_ handler: @escaping ([EmbedImage], Int) -> Void) { self.handler = handler }
}

struct ReportAction {
    let handler: (ReportTarget) -> Void
    func callAsFunction(_ target: ReportTarget) { handler(target) }
    init(_ handler: @escaping (ReportTarget) -> Void) { self.handler = handler }
}

struct InspectRecordAction {
    let handler: (PostView) -> Void
    func callAsFunction(_ post: PostView) { handler(post) }
    init(_ handler: @escaping (PostView) -> Void) { self.handler = handler }
}

private struct OpenImagesKey: EnvironmentKey {
    static let defaultValue = OpenImagesAction { _, _ in }
}

private struct ReportKey: EnvironmentKey {
    static let defaultValue = ReportAction { _ in }
}

private struct InspectRecordKey: EnvironmentKey {
    static let defaultValue = InspectRecordAction { _ in }
}

extension EnvironmentValues {
    var openImages: OpenImagesAction {
        get { self[OpenImagesKey.self] }
        set { self[OpenImagesKey.self] = newValue }
    }

    var report: ReportAction {
        get { self[ReportKey.self] }
        set { self[ReportKey.self] = newValue }
    }

    var inspectRecord: InspectRecordAction {
        get { self[InspectRecordKey.self] }
        set { self[InspectRecordKey.self] = newValue }
    }
}

struct OverlayHostModifier: ViewModifier {
    @State private var gallery: Gallery?
    @State private var inspected: PostView?
    @State private var reported: ReportTarget?

    func body(content: Content) -> some View {
        content
            .environment(\.openImages, OpenImagesAction { images, index in
                guard !images.isEmpty else { return }
                gallery = Gallery(images: images, index: index)
            })
            .environment(\.inspectRecord, InspectRecordAction { post in
                inspected = post
            })
            .environment(\.report, ReportAction { target in
                reported = target
            })
            #if os(iOS)
            .fullScreenCover(item: $gallery) { item in
                ImageViewer(images: item.images, index: item.index)
            }
            #else
            // A sheet on macOS is a panel sized to its content, and a picture
            // has no opinion about its size — it opened small, with the post
            // still showing around it. An overlay fills the window instead,
            // whatever the window has been dragged to.
            .overlay {
                if let item = gallery {
                    ImageViewer(images: item.images, index: item.index) { gallery = nil }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: gallery?.id)
            #endif
            .sheet(item: $reported) { target in
                ReportView(target: target)
                    .presentationBackground(Theme.Palette.background)
                    .sheetSize()
            }
            .sheet(item: $inspected) { post in
                RecordInspectorView(post: post)
                    .presentationBackground(Theme.Palette.background)
                    .sheetSize()
            }
    }

    private struct Gallery: Identifiable {
        let images: [EmbedImage]
        let index: Int
        var id: String { (images.first?.id ?? "gallery") + "#\(index)" }
    }
}

extension View {
    func withOverlays() -> some View { modifier(OverlayHostModifier()) }
}
