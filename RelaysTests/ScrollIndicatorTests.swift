//
//  ScrollIndicatorTests.swift
//  RelaysTests
//
//  On iOS a scroll indicator fades out on its own and nobody sees it. On macOS
//  it sits there, grey and system-styled, in the middle of a design that has no
//  other grey system parts. Five screens were missed one at a time; this looks
//  at all of them at once.
//

import Testing
import Foundation

@Suite("Scroll indicators")
struct ScrollIndicatorTests {

    /// A scrolling container the platform will draw a bar for. `ScrollViewReader`
    /// is not one — it is a coordinate helper and scrolls nothing itself.
    private static let scrollable = /ScrollView(?!Reader)|TextEditor\(/
    private static let silenced = /\.scrollIndicators\(/

    /// The sources sit next to this file, not in the bundle, so the path is the
    /// one baked in at compile time.
    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RelaysTests
            .deletingLastPathComponent()   // repository
            .appendingPathComponent("Relays")
    }

    /// Counting the source as written counts prose too — a doc comment that
    /// merely names a scrolling container used to fail this test, which makes it
    /// a trap rather than a guard. Comments are stripped first.
    static func code(in source: String) -> String {
        source.components(separatedBy: .newlines)
            .map { line -> String in
                guard let slashes = line.range(of: "//") else { return line }
                return String(line[line.startIndex..<slashes.lowerBound])
            }
            .joined(separator: "\n")
    }

    private static func swiftFiles() -> [URL] {
        guard let walk = FileManager.default.enumerator(at: sourceRoot,
                                                        includingPropertiesForKeys: nil) else {
            return []
        }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("Every scrolling container hides its bar")
    func everyContainerIsSilenced() throws {
        let files = Self.swiftFiles()

        // Running somewhere without the checkout — nothing to say either way.
        guard !files.isEmpty else { return }

        var offenders: [String] = []
        for file in files {
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let source = Self.code(in: raw)
            let containers = source.matches(of: Self.scrollable).count
            let hidden = source.matches(of: Self.silenced).count
            if containers > hidden {
                offenders.append("\(file.lastPathComponent): \(containers) scrolling, \(hidden) silenced")
            }
        }

        #expect(offenders.isEmpty,
                "Scroll bars visible on macOS in:\n\(offenders.joined(separator: "\n"))")
    }

    /// A `PhotosPicker` is a button, and a button with no style is a system
    /// button. On iOS that is invisible; on macOS it is a grey bordered box in
    /// the middle of a design that has no other system parts. Both pickers in
    /// the compose sheet were exactly that.
    @Test("Every picture picker is styled by the app, not by the system")
    func pickersAreStyled() throws {
        let files = Self.swiftFiles()
        guard !files.isEmpty else { return }

        var offenders: [String] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: .newlines)
            for (number, line) in lines.enumerated() where line.contains("PhotosPicker(") {
                // The style sits after the label closure, which is a handful of
                // lines further down.
                let window = lines[number..<min(number + 45, lines.count)]
                if !window.contains(where: { $0.contains(".buttonStyle(.plain)") }) {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        #expect(offenders.isEmpty,
                "System button chrome on macOS at:\n\(offenders.joined(separator: "\n"))")
    }
}
