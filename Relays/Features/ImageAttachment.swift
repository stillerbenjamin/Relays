//
//  ImageAttachment.swift
//  Relays
//
//  Pictures picked for a post: prepared on the device before they are uploaded.
//  The network rejects anything over roughly a megabyte, so each one is scaled
//  and compressed until it fits.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class ImageAttachment: Identifiable {
    let id = UUID()
    /// JPEG data as it will be uploaded.
    private(set) var data: Data
    private(set) var pixelSize: CGSize
    var alt: String = ""

    var aspectRatio: EmbedImage.AspectRatio {
        .init(width: Int(pixelSize.width), height: Int(pixelSize.height))
    }

    var byteCount: Int { data.count }

    #if canImport(UIKit)
    var preview: Image? { UIImage(data: data).map { Image(uiImage: $0) } }
    #else
    var preview: Image? { NSImage(data: data).map { Image(nsImage: $0) } }
    #endif

    private init(data: Data, pixelSize: CGSize) {
        self.data = data
        self.pixelSize = pixelSize
    }

    /// The largest edge the network is happy with, and the size budget per image.
    private static let maximumEdge: CGFloat = 2000
    private static let byteBudget = 900_000

    /// Loads a picked item and prepares it. Returns nil for anything that is not
    /// a readable image.
    static func load(from item: PhotosPickerItem) async -> ImageAttachment? {
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return nil }
        return prepare(raw)
    }

    /// Scales the picture down until it is within budget, trading quality first
    /// and size second — the order that keeps text in screenshots readable.
    static func prepare(_ raw: Data) -> ImageAttachment? {
        #if canImport(UIKit)
        guard var image = UIImage(data: raw) else { return nil }

        if max(image.size.width, image.size.height) > maximumEdge {
            image = resize(image, longestEdge: maximumEdge)
        }

        var quality: CGFloat = 0.85
        var encoded = image.jpegData(compressionQuality: quality)

        while let current = encoded, current.count > byteBudget, quality > 0.35 {
            quality -= 0.12
            encoded = image.jpegData(compressionQuality: quality)
        }

        // Still too large: step the pixels down and try once more.
        while let current = encoded, current.count > byteBudget,
              max(image.size.width, image.size.height) > 600 {
            image = resize(image, longestEdge: max(image.size.width, image.size.height) * 0.75)
            encoded = image.jpegData(compressionQuality: quality)
        }

        guard let final = encoded else { return nil }
        return ImageAttachment(data: final, pixelSize: image.size)
        #else
        guard let image = NSImage(data: raw), let start = jpeg(image, quality: 0.85) else { return nil }

        var size = pixelSize(of: image)
        var working = image
        if max(size.width, size.height) > maximumEdge {
            working = resize(image, longestEdge: maximumEdge)
            size = pixelSize(of: working)
        }

        var quality: CGFloat = 0.85
        var encoded = jpeg(working, quality: quality) ?? start

        while encoded.count > byteBudget, quality > 0.35 {
            quality -= 0.12
            encoded = jpeg(working, quality: quality) ?? encoded
        }

        while encoded.count > byteBudget, max(size.width, size.height) > 600 {
            working = resize(working, longestEdge: max(size.width, size.height) * 0.75)
            size = pixelSize(of: working)
            encoded = jpeg(working, quality: quality) ?? encoded
        }

        return ImageAttachment(data: encoded, pixelSize: size)
        #endif
    }

    #if !canImport(UIKit)
    /// NSImage reports point sizes; the pixel dimensions are what the network wants.
    private static func pixelSize(of image: NSImage) -> CGSize {
        guard let rep = image.representations.first else { return image.size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    private static func jpeg(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private static func resize(_ image: NSImage, longestEdge: CGFloat) -> NSImage {
        let current = pixelSize(of: image)
        let scale = longestEdge / max(current.width, current.height)
        let target = NSSize(width: (current.width * scale).rounded(),
                            height: (current.height * scale).rounded())
        let output = NSImage(size: target)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        output.unlockFocus()
        return output
    }
    #endif

    #if canImport(UIKit)
    private static func resize(_ image: UIImage, longestEdge: CGFloat) -> UIImage {
        let scale = longestEdge / max(image.size.width, image.size.height)
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #endif
}
