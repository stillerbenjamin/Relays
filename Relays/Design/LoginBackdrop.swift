//
//  LoginBackdrop.swift
//  Relays
//
//  The ground the sign-in stands on: parallel traces, the way a relay carries
//  what passes through it. Drawn rather than shipped as a picture — the app has
//  four grounds and every screen size there is, and a file would have to be
//  right for all of them at once.
//
//  It is deliberately faint. This is behind a form somebody has to read.
//
//  The traces can be fed from the live firehose: the geometry stays seeded so
//  nothing jumps around, and only the brightness moves. What the screen then
//  shows is the last minute of the network, oldest at the top — before anybody
//  has signed in to anything.
//

import SwiftUI

struct LoginBackdrop: View {
    /// How far into the fade-in the backdrop is. The traces arrive after the
    /// wordmark, so the screen settles rather than starting busy.
    var progress: Double = 1
    /// A minute of the network, oldest first. Without it the traces keep their
    /// own seeded brightness — which is what previews, snapshots and a missing
    /// connection all get.
    var buckets: [Int]?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let traces = Self.traces(in: size, buckets: buckets)
            let ink = Theme.Palette.textPrimary

            Canvas { context, _ in
                for trace in traces {
                    let y = trace.y * size.height
                    let start = trace.start * size.width
                    let end = min(size.width, start + trace.length * size.width)
                    guard end > start else { continue }

                    var line = Path()
                    line.move(to: CGPoint(x: start, y: y))
                    line.addLine(to: CGPoint(x: end, y: y))
                    context.stroke(line,
                                   with: .color(ink.opacity(trace.opacity * progress)),
                                   lineWidth: trace.width)

                    // One brighter stretch on some traces: what is travelling.
                    guard let packet = trace.packet else { continue }
                    let from = start + (end - start) * packet
                    let to = min(end, from + (end - start) * 0.16)
                    var lit = Path()
                    lit.move(to: CGPoint(x: from, y: y))
                    lit.addLine(to: CGPoint(x: to, y: y))
                    // The link colour, not the accent: on the blue ground the
                    // accent *is* the ground, and the lit stretch would vanish.
                    context.stroke(lit,
                                   with: .color(Theme.Palette.link
                                        .opacity(min(0.5, trace.opacity * 4) * progress)),
                                   lineWidth: trace.width)
                }
            }
            // The middle stays quiet so the wordmark and the fields sit on
            // something even rather than on a line.
            .mask(
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.15), location: 0.36),
                    .init(color: .white.opacity(0.15), location: 0.64),
                    .init(color: .white, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - The traces

    private struct Trace {
        let y: Double
        let start: Double
        let length: Double
        let width: Double
        let opacity: Double
        let packet: Double?
    }

    /// One trace's share of the window, oldest at the top. A quiet second is a
    /// dim line, not a missing one — the relay is still there when nothing is
    /// passing through it.
    static func level(_ index: Int, of count: Int, buckets: [Int]) -> Double {
        guard count > 1, !buckets.isEmpty else { return 1 }
        let position = Double(index) / Double(count - 1)
        let bucket = buckets[min(buckets.count - 1, Int(position * Double(buckets.count - 1)))]
        let peak = max(buckets.max() ?? 1, 1)
        return 0.25 + 0.75 * min(1, Double(bucket) / Double(peak))
    }

    /// Seeded, not random: the same screen has to look the same on every redraw,
    /// or the background flickers whenever anything above it changes.
    private static func traces(in size: CGSize, buckets: [Int]? = nil) -> [Trace] {
        let count = size.height > 700 ? 34 : 26
        var generator = Seeded(seed: 20_260_830)

        return (0..<count).map { index in
            let live = buckets.map { level(index, of: count, buckets: $0) }
            let band = Double(index) / Double(count - 1)
            // A little scatter around an even spacing: evenly spaced lines read
            // as a pattern, scattered ones as signal.
            let y = min(0.995, max(0.005, band + generator.next(-0.012, 0.012)))
            let width = generator.next(0.6, 1.6)

            return Trace(
                y: y,
                start: generator.next(-0.15, 0.55),
                length: generator.next(0.25, 0.95),
                width: width,
                // Thin lines stay quieter than thick ones, so the field has depth.
                opacity: generator.next(0.045, 0.13) * (width > 1.1 ? 1.25 : 0.8)
                    * (live ?? 1),
                // Live, a lit stretch means that second carried something.
                packet: {
                    let seeded = generator.next(0, 1) > 0.62
                    let offset = generator.next(0.05, 0.7)
                    guard let live else { return seeded ? offset : nil }
                    return live > 0.45 ? offset : nil
                }())
        }
    }

    /// A small deterministic generator. `Double.random` would give a different
    /// picture on every launch, and SwiftUI redraws this view often.
    private struct Seeded {
        private var state: UInt64

        init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

        mutating func next(_ lower: Double, _ upper: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state >> 11) & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
            return lower + unit * (upper - lower)
        }
    }
}

/// The backdrop wired to the firehose.
///
/// It holds the stream only while the sign-in is on screen and the app is in
/// front, and only if the reader has left the pulse switched on — the same
/// setting that governs the line under the timeline header. Switched off, or
/// with no connection, the traces fall back to their seeded pattern and nothing
/// about the screen looks broken.
struct LiveLoginBackdrop: View {
    var progress: Double = 1

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var phase

    @State private var holding = false

    var body: some View {
        LoginBackdrop(progress: progress, buckets: settings.relayPulse ? app.relay.buckets : nil)
            .onAppear { hold() }
            .onDisappear { release() }
            .onChange(of: phase) { _, current in
                current == .active ? hold() : release()
            }
            .onChange(of: settings.relayPulse) { _, wanted in
                wanted ? hold() : release()
            }
    }

    private func hold() {
        guard !Self.isPreview else { return }
        guard !holding, settings.relayPulse, progress > 0 else { return }
        holding = true
        app.relay.attach()
    }

    private func release() {
        guard holding else { return }
        holding = false
        app.relay.detach()
    }

    /// Xcode's preview host. Opening a websocket there shows nothing and keeps
    /// the process working for it.
    private static let isPreview =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
