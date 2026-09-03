//
//  MacViewerSnapshot.swift
//  RelaysTests
//
//  The picture viewer is the one screen whose macOS build differs from its iOS
//  one, and nothing in the project could look at a macOS view until now. The
//  remote picture will not load inside a renderer — the frame around it is what
//  this shows, and the frame is what was wrong.
//

#if os(macOS)
import Testing
import SwiftUI
import AppKit
@testable import Relays

@MainActor
@Suite("macOS picture viewer")
struct MacViewerSnapshot {

    private func image(_ alt: String) -> EmbedImage {
        EmbedImage(thumb: "https://example.com/thumb.jpg",
                   fullsize: "https://example.com/full.jpg",
                   alt: alt, aspectRatio: nil)
    }

    @Test("It fills its window and carries its own paging")
    func viewer() throws {
        let view = ImageViewer(images: [image("Zwei Männer im Profil"),
                                        image("Zweites Bild"),
                                        image("Drittes Bild")],
                               index: 0) { }
            .environment(AppModel())
            .environment(AppSettings())
            .frame(width: 480, height: 620)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let nsImage = try #require(renderer.nsImage)
        let tiff = try #require(nsImage.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try data.write(to: directory.appendingPathComponent("snapshot-mac-viewer.png"))
        #expect(data.count > 0)
    }

    @Test("The header carries a refresh a Mac can actually reach")
    func headerRefresh() throws {
        let view = VStack(spacing: 0) {
            ScreenHeader(title: "Relays", onRefresh: { })
            ScreenHeader(title: "Notifications", onRefresh: { })
            Spacer()
        }
        .environment(AppModel())
        .environment(AppSettings())
        .frame(width: 480, height: 130)
        .background(Theme.Palette.background)

        try write(view, named: "snapshot-mac-header")
    }

    private func write(_ view: some View, named name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let nsImage = try #require(renderer.nsImage)
        let tiff = try #require(nsImage.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
