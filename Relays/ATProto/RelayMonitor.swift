//
//  RelayMonitor.swift
//  Relays
//
//  A minute of the network, kept in memory. Jetstream carries every record the
//  moment it is written; this turns that stream into something an interface can
//  show without anyone having to ask a server a question.
//

import Foundation
import Observation

/// The firehose delivers faster than any view should redraw. Events land here
/// from the socket's thread and are drained onto the main actor four times a
/// second. A lock rather than an actor: one append per record, and hopping
/// executors for each of them costs more than the work itself.
final class RelayBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var pending: [RadarEvent] = []

    /// Roughly two seconds of the full stream. Anything older has been missed.
    private static let limit = 800

    func append(_ event: RadarEvent) {
        lock.lock()
        pending.append(event)
        if pending.count > Self.limit {
            pending.removeFirst(pending.count - Self.limit)
        }
        lock.unlock()
    }

    func drain() -> [RadarEvent] {
        lock.lock()
        let events = pending
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
        return events
    }
}

@MainActor
@Observable
final class RelayMonitor {

    enum Status: Equatable {
        case idle, connecting, live
        case failed(String)
    }

    /// One second per bucket, oldest first.
    static let window = 60

    /// Accounts looked up per session. The ranking is a sample, not a census —
    /// resolving every DID off the firehose would hammer the directory.
    static let sampleCeiling = 250

    private(set) var status: Status = .idle
    private(set) var buckets: [Int] = Array(repeating: 0, count: RelayMonitor.window)
    private(set) var counts: [RadarEvent.Kind: Int] = [:]
    private(set) var seen = 0
    private(set) var latest: [RadarEvent] = []
    private(set) var servers: [String: Int] = [:]
    private(set) var sampledAccounts = 0
    private(set) var selfHosted = 0
    private(set) var stream: RadarStream = .posts
    private(set) var host: JetstreamHost = .usEast2
    private(set) var startedAt: Date?

    private let client = JetstreamClient()
    private let buffer = RelayBuffer()
    private let directory: PDSDirectory

    private var subscribers = 0
    private var ticker: Task<Void, Never>?
    private var bucketStart = Date()
    private var latencies: [Double] = []
    private var awaitingOrigin: [String] = []
    private var askedDIDs: Set<String> = []
    private var awaitingResult: Set<String> = []
    private var flushes = 0
    private var handlersSet = false

    init(directory: PDSDirectory) {
        self.directory = directory
    }

    // MARK: - Readings

    /// Records per second, averaged over the last ten completed seconds. The
    /// second still being filled is left out or the number would sag every tick.
    var perSecond: Double { Self.perSecond(in: buckets) }

    nonisolated static func perSecond(in buckets: [Int]) -> Double {
        let complete = buckets.dropLast().suffix(10)
        guard !complete.isEmpty else { return 0 }
        return Double(complete.reduce(0, +)) / Double(complete.count)
    }

    /// Median time from the author's own timestamp to arrival here.
    var latency: Double? {
        guard !latencies.isEmpty else { return nil }
        let sorted = latencies.sorted()
        return sorted[sorted.count / 2]
    }

    /// Servers by how many sampled accounts they host, busiest first.
    var serverRanking: [(host: String, count: Int)] {
        servers.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (host: $0.key, count: $0.value) }
    }

    var isRunning: Bool { subscribers > 0 }

    // MARK: - Lifecycle

    /// Views ask for the stream while they are on screen and let go when they
    /// leave. The socket is open only while somebody is looking.
    func attach() {
        subscribers += 1
        guard subscribers == 1 else { return }

        installHandlers()
        bucketStart = Date()
        startedAt = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.flush()
            }
        }
        Task { await client.start() }
    }

    func detach() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }

        ticker?.cancel()
        ticker = nil
        Task { await client.stop() }
        status = .idle
        startedAt = nil
    }

    func setStream(_ value: RadarStream) {
        guard value != stream else { return }
        stream = value
        resetReadings()
        Task { await client.setStream(value) }
    }

    func setHost(_ value: JetstreamHost) {
        guard value != host else { return }
        host = value
        resetReadings()
        Task { await client.setHost(value) }
    }

    private func installHandlers() {
        guard !handlersSet else { return }
        handlersSet = true

        // Both handlers are made here, where `self` is captured weakly exactly
        // once. Building them inside the Task captured the enclosing closure's
        // `self` a second time, which is a data race the compiler is right about.
        let sink = buffer
        let onEvent: @Sendable (RadarEvent) -> Void = { sink.append($0) }
        let onState: @Sendable (JetstreamClient.State) -> Void = { [weak self] state in
            Task { @MainActor in self?.absorb(state) }
        }

        Task { [client] in
            await client.setHandlers(event: onEvent, state: onState)
        }
    }

    private func absorb(_ state: JetstreamClient.State) {
        switch state {
        case .idle: status = .idle
        case .connecting: status = .connecting
        case .live: status = .live
        case .failed(let message): status = .failed(message)
        }
    }

    private func resetReadings() {
        buckets = Array(repeating: 0, count: Self.window)
        counts = [:]
        servers = [:]
        sampledAccounts = 0
        selfHosted = 0
        seen = 0
        latest = []
        latencies = []
        askedDIDs = []
        awaitingResult = []
        awaitingOrigin = []
        bucketStart = Date()
        startedAt = Date()
    }

    // MARK: - Drain

    private func flush() {
        rotate()
        flushes += 1

        ingest(buffer.drain())

        // One directory lookup a second, no more.
        if flushes % 4 == 0 { sampleOrigins() }
        collectOrigins()
    }

    /// Everything a drained batch changes. Separate from the timer so it can be
    /// driven with a known batch instead of a live socket.
    func ingest(_ events: [RadarEvent]) {
        guard !events.isEmpty else { return }

        buckets[buckets.count - 1] += events.count
        seen += events.count

        for event in events {
            counts[event.kind, default: 0] += 1
            if let sample = Self.latency(of: event) { latencies.append(sample) }
            enqueueForOrigin(event.did)
        }
        if latencies.count > 400 { latencies.removeFirst(latencies.count - 400) }
        latest = Array((events.reversed() + latest).prefix(40))
    }

    /// Buckets are wall-clock, not tick-clock: a stalled connection has to show
    /// as a minute of silence rather than a frozen line.
    private func rotate() {
        let elapsed = Int(Date().timeIntervalSince(bucketStart))
        guard elapsed > 0 else { return }
        bucketStart = bucketStart.addingTimeInterval(Double(elapsed))
        buckets = Self.shifted(buckets, by: elapsed)
    }

    /// Moves the window on by whole seconds. Silence longer than the window
    /// leaves it empty rather than wrapping stale counts around.
    nonisolated static func shifted(_ buckets: [Int], by seconds: Int) -> [Int] {
        guard seconds > 0 else { return buckets }
        guard seconds < buckets.count else {
            return Array(repeating: 0, count: buckets.count)
        }
        return Array(buckets.dropFirst(seconds)) + Array(repeating: 0, count: seconds)
    }

    private func enqueueForOrigin(_ did: String) {
        guard askedDIDs.count < Self.sampleCeiling,
              !askedDIDs.contains(did),
              awaitingOrigin.count < 40 else { return }
        awaitingOrigin.append(did)
    }

    private func sampleOrigins() {
        guard !awaitingOrigin.isEmpty else { return }
        let did = awaitingOrigin.removeFirst()
        guard !askedDIDs.contains(did) else { return }
        askedDIDs.insert(did)
        awaitingResult.insert(did)
        directory.resolve(did)
    }

    /// The directory answers on its own schedule; tally whatever has landed.
    private func collectOrigins() {
        guard !awaitingResult.isEmpty else { return }
        for did in awaitingResult {
            guard let origin = directory.origin(for: did) else { continue }
            awaitingResult.remove(did)
            servers[origin.short, default: 0] += 1
            sampledAccounts += 1
            if !origin.isBlueskyHosted { selfHosted += 1 }
        }
    }

    // MARK: - Latency

    // ISO8601DateFormatter is thread-safe for parsing, and these are read from
    // the drain on the main actor and from tests on whichever one they run.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Clocks on the network are not synchronised and some clients backdate.
    /// Absurd values are dropped rather than averaged in.
    nonisolated static func latency(of event: RadarEvent) -> Double? {
        guard let text = event.createdAt,
              let written = fractional.date(from: text) ?? plain.date(from: text)
        else { return nil }

        let delta = event.receivedAt.timeIntervalSince(written)
        guard delta > -5, delta < 120 else { return nil }
        return delta
    }
}
