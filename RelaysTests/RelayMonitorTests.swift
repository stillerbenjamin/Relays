//
//  RelayMonitorTests.swift
//  RelaysTests
//

import Testing
import Foundation
@testable import Relays

@Suite("Relay readings")
struct RelayMonitorTests {

    private func event(kind: RadarEvent.Kind = .post,
                       did: String = "did:plc:a",
                       createdAt: String? = nil,
                       received: Date = Date()) -> RadarEvent {
        RadarEvent(did: did, rkey: UUID().uuidString, cid: nil, kind: kind,
                   text: kind == .post ? "hello" : "", subject: nil, langs: [],
                   hasMedia: false, createdAt: createdAt, receivedAt: received)
    }

    // MARK: - Window

    @Test("The window moves on by whole seconds and drops what fell off")
    func shifting() {
        let window = [1, 2, 3, 4, 5]

        #expect(RelayMonitor.shifted(window, by: 0) == window)
        #expect(RelayMonitor.shifted(window, by: 1) == [2, 3, 4, 5, 0])
        #expect(RelayMonitor.shifted(window, by: 3) == [4, 5, 0, 0, 0])
        // Silence longer than the window must not wrap stale counts around.
        #expect(RelayMonitor.shifted(window, by: 5) == [0, 0, 0, 0, 0])
        #expect(RelayMonitor.shifted(window, by: 900) == [0, 0, 0, 0, 0])
        #expect(RelayMonitor.shifted(window, by: -2) == window)
    }

    @Test("The rate leaves out the second still being filled")
    func rate() {
        // Ten complete seconds of four, and a partial second that must not count.
        let buckets = Array(repeating: 4, count: 10) + [1]
        #expect(RelayMonitor.perSecond(in: buckets) == 4)

        #expect(RelayMonitor.perSecond(in: [7]) == 0)
        #expect(RelayMonitor.perSecond(in: []) == 0)
    }

    // MARK: - Latency

    @Test("Latency is read from either timestamp shape")
    func latencyShapes() throws {
        let received = try #require(ISO8601DateFormatter().date(from: "2026-08-29T12:00:02Z"))

        let fractional = event(createdAt: "2026-08-29T12:00:00.500Z", received: received)
        let plain = event(createdAt: "2026-08-29T12:00:00Z", received: received)

        #expect(try #require(RelayMonitor.latency(of: fractional)) == 1.5)
        #expect(try #require(RelayMonitor.latency(of: plain)) == 2)
    }

    @Test("Unsynchronised clocks are dropped, not averaged in")
    func latencyOutliers() {
        let received = ISO8601DateFormatter().date(from: "2026-08-29T12:00:00Z")!

        // A client that backdates by an hour, and one whose clock runs ahead.
        #expect(RelayMonitor.latency(of: event(createdAt: "2026-08-29T11:00:00Z",
                                               received: received)) == nil)
        #expect(RelayMonitor.latency(of: event(createdAt: "2026-08-29T12:01:00Z",
                                               received: received)) == nil)
        #expect(RelayMonitor.latency(of: event(createdAt: nil)) == nil)
        #expect(RelayMonitor.latency(of: event(createdAt: "not a date")) == nil)
    }

    // MARK: - Ingest

    @MainActor
    @Test("A batch lands in the newest second and is counted by kind")
    func ingest() {
        let monitor = RelayMonitor(directory: PDSDirectory())

        monitor.ingest([event(kind: .post), event(kind: .post), event(kind: .like)])

        #expect(monitor.seen == 3)
        #expect(monitor.counts[.post] == 2)
        #expect(monitor.counts[.like] == 1)
        #expect(monitor.buckets.last == 3)
        #expect(monitor.buckets.dropLast().allSatisfy { $0 == 0 })
        // Newest first, so the ticker reads top down.
        #expect(monitor.latest.count == 3)
        #expect(monitor.latest.first?.kind == .like)
    }

    @MainActor
    @Test("The ticker keeps a bounded tail")
    func tickerBound() {
        let monitor = RelayMonitor(directory: PDSDirectory())
        monitor.ingest((0..<200).map { _ in event() })

        #expect(monitor.seen == 200)
        #expect(monitor.latest.count == 40)
    }

    @MainActor
    @Test("An empty batch changes nothing")
    func emptyBatch() {
        let monitor = RelayMonitor(directory: PDSDirectory())
        monitor.ingest([])

        #expect(monitor.seen == 0)
        #expect(monitor.buckets.allSatisfy { $0 == 0 })
        #expect(monitor.latency == nil)
    }

    // MARK: - Formatting

    @Test("Small rates keep a decimal, large ones drop it")
    func rateFormatting() {
        #expect(RelayView.rate(3.42) == "3.4")
        #expect(RelayView.rate(0) == "0.0")
        #expect(RelayView.rate(41.6) == "42")
    }
}

// MARK: - The sign-in backdrop

@Suite("Live backdrop")
struct LoginBackdropTests {

    /// The traces read top to bottom as oldest to newest, so a reader watching
    /// the sign-in screen sees the last minute arrive from below.
    @Test("The top trace is the oldest second and the bottom the newest")
    func mapsTimeDownTheScreen() {
        var window = Array(repeating: 0, count: 60)
        window[0] = 100    // a minute ago
        window[59] = 100   // right now

        let count = 30
        #expect(LoginBackdrop.level(0, of: count, buckets: window) == 1)
        #expect(LoginBackdrop.level(count - 1, of: count, buckets: window) == 1)
        // Everything between those two was quiet.
        #expect(LoginBackdrop.level(count / 2, of: count, buckets: window) == 0.25)
    }

    @Test("A quiet second dims a trace instead of removing it")
    func quietIsNotGone() {
        let silent = Array(repeating: 0, count: 60)
        // The relay is still there when nothing is passing through it.
        #expect(LoginBackdrop.level(5, of: 30, buckets: silent) == 0.25)
        #expect(LoginBackdrop.level(5, of: 30, buckets: silent) > 0)
    }

    @Test("Brightness is measured against the busiest second, not an absolute")
    func scalesToThePeak() {
        // Two windows of different size but the same shape read the same, so a
        // quiet night does not leave the screen blank.
        let busy = [10, 20, 40]
        let calm = [1, 2, 4]
        for index in 0..<3 {
            #expect(LoginBackdrop.level(index, of: 3, buckets: busy)
                    == LoginBackdrop.level(index, of: 3, buckets: calm))
        }
    }

    @Test("With no stream at all the traces keep their own brightness")
    func fallsBack() {
        #expect(LoginBackdrop.level(0, of: 30, buckets: []) == 1)
        #expect(LoginBackdrop.level(0, of: 1, buckets: [5]) == 1)
    }
}
