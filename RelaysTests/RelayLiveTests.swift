//
//  RelayLiveTests.swift
//  RelaysTests
//
//  Talks to the real firehose. Jetstream is public and unauthenticated, so this
//  needs no account — but it does need the network, which is why it does not run
//  with the rest. Run it by hand after touching the monitor:
//
//    xcodebuild test -only-testing:RelaysTests/RelayLiveTests …
//

import Testing
import Foundation
@testable import Relays

@Suite("Relay against the live firehose",
       .disabled("Needs the network; run by hand after touching the monitor"))
struct RelayLiveTests {

    @MainActor
    @Test("The stream reaches the readings")
    func liveStream() async throws {
        let monitor = RelayMonitor(directory: PDSDirectory())
        monitor.attach()
        defer { monitor.detach() }

        // Connecting and filling one bucket takes a moment; give it fifteen
        // seconds before calling the network at fault.
        var waited = 0.0
        while monitor.seen < 50, waited < 15 {
            try await Task.sleep(for: .milliseconds(500))
            waited += 0.5
        }

        #expect(monitor.status == .live)
        #expect(monitor.seen >= 50)
        #expect(monitor.latest.first?.kind == .post)
        // Every post off the wire carries text, or the decoder dropped it.
        #expect(monitor.latest.allSatisfy { !$0.text.isEmpty })

        // Real timestamps, real arrival times: the median has to be a plausible
        // number of milliseconds, not a parse failure.
        let latency = try #require(monitor.latency)
        #expect(latency > 0 && latency < 30)

        print("live firehose: \(monitor.seen) records in \(waited)s, "
              + "median latency \(Int(latency * 1000)) ms")
    }
}
