//
//  VideoTests.swift
//  RelaysTests
//
//  The video path has three hosts in it — the account's server mints the token,
//  the video service takes the file, and the job lives on the video service too.
//  Sending any step to the wrong one leaves an upload that never finishes.
//

import Testing
import Foundation
@testable import Relays

@Suite("Video jobs", .serialized)
struct VideoJobTests {

    private static let session = ATSession(accessJwt: "access-1", refreshJwt: "refresh-1",
                                           handle: "tester.test", did: "did:plc:tester",
                                           email: nil, service: "https://pds.test")

    private func makeClient() -> ATProtoClient {
        ATProtoClient(service: "https://pds.test", session: Self.session,
                      configuration: StubTransport.configuration)
    }

    private static let running = """
    {"jobStatus":{"jobId":"job-1","state":"JOB_STATE_ENCODING","progress":40,
                  "did":"did:plc:tester"}}
    """
    private static let done = """
    {"jobStatus":{"jobId":"job-1","state":"JOB_STATE_COMPLETED","progress":100,
                  "did":"did:plc:tester",
                  "blob":{"$type":"blob","ref":{"$link":"bafyvideo"},
                          "mimeType":"video/mp4","size":900}}}
    """

    // MARK: - Where the job lives

    /// The job lives where the file went. Asking the account's own server for it
    /// is what kept an upload spinning forever: the PDS has never heard of it.
    @Test("The job is polled on the video service, not on the account's server")
    func jobIsPolledOnTheVideoService() async throws {
        StubTransport.reset([
            .init(body: Data(Self.done.utf8), path: "app.bsky.video.getJobStatus"),
        ])

        let job = try await makeClient().videoJob(id: "job-1")
        #expect(job.isFinished)

        let request = try #require(StubTransport.requests.first)
        #expect(request.url?.host == "video.bsky.app")
        #expect(request.url?.query?.contains("jobId=job-1") == true)
        // The job id is the secret; no session token is sent with it.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - What the file is called

    @Test("The file is announced as what it is")
    func contentTypeFollowsTheFile() async throws {
        for (name, type) in [("clip.mp4", "video/mp4"),
                             ("clip.MOV", "video/quicktime"),
                             ("clip.m4v", "video/x-m4v"),
                             ("clip", "video/mp4")] {
            StubTransport.reset([
                .init(body: Data(#"{"token":"t"}"#.utf8), path: "getServiceAuth"),
                .init(body: Data(Self.running.utf8), path: "uploadVideo"),
            ])
            _ = try await makeClient().uploadVideo(data: Data([0]), filename: name)

            let upload = try #require(StubTransport.requests.last)
            #expect(upload.value(forHTTPHeaderField: "Content-Type") == type,
                    "\(name) was announced wrongly")
        }
    }

    // MARK: - Waiting

    @Test("Waiting reports progress and ends with the blob")
    func waitsForTheBlob() async throws {
        StubTransport.reset([
            .init(body: Data(Self.running.utf8), path: "getJobStatus"),
            .init(body: Data(Self.done.utf8), path: "getJobStatus"),
        ])

        let start = VideoJob(jobId: "job-1", state: "JOB_STATE_ENCODING", progress: 10,
                             blob: nil, error: nil, message: nil)
        let reported = Reported()
        let blob = try await makeClient().awaitVideo(job: start) { reported.add($0) }

        #expect(blob.ref.link == "bafyvideo")
        #expect(reported.values.contains(10))
    }

    /// A poll that fails is not an upload that failed — the job keeps running on
    /// the service. Only a run of failures is worth giving up on.
    @Test("A dropped poll does not throw the video away")
    func toleratesADroppedPoll() async throws {
        StubTransport.reset([
            .init(error: URLError(.networkConnectionLost), path: "getJobStatus"),
            .init(error: URLError(.networkConnectionLost), path: "getJobStatus"),
            .init(body: Data(Self.done.utf8), path: "getJobStatus"),
        ])

        let start = VideoJob(jobId: "job-1", state: "JOB_STATE_ENCODING", progress: 0,
                             blob: nil, error: nil, message: nil)
        let blob = try await makeClient().awaitVideo(job: start) { _ in }
        #expect(blob.ref.link == "bafyvideo")
    }

    /// The service answers a refusal flat, with an `error` on the job itself,
    /// rather than in the wrapper. Read only the wrapper and a refusal arrives as
    /// "could not read the response".
    @Test("A refusal arrives as what it is, not as a decoding failure")
    func flatErrorIsRead() async throws {
        StubTransport.reset([
            .init(body: Data(#"{"did":"","error":"invalid jobId","jobId":"","state":""}"#.utf8),
                  path: "getJobStatus"),
        ])

        await #expect(throws: ATProtoError.self) {
            _ = try await makeClient().videoJob(id: "nope")
        }
    }

    @Test("A failed job says why")
    func failedJob() async throws {
        StubTransport.reset([])
        let failed = VideoJob(jobId: "job-1", state: "JOB_STATE_FAILED", progress: nil,
                              blob: nil, error: "unsupported", message: "That file is not video.",
                              )
        do {
            _ = try await makeClient().awaitVideo(job: failed) { _ in }
            Issue.record("expected it to throw")
        } catch let error as ATProtoError {
            #expect(error.errorDescription == "That file is not video.")
        }
    }

    /// A job that says it is done but hands back nothing is not a success. It
    /// used to be waited on until the whole thing timed out.
    @Test("Finished without a blob is a failure, not a wait")
    func finishedWithoutBlob() async throws {
        StubTransport.reset([])
        let empty = VideoJob(jobId: "job-1", state: "JOB_STATE_COMPLETED", progress: 100,
                             blob: nil, error: nil, message: nil)
        await #expect(throws: ATProtoError.self) {
            _ = try await makeClient().awaitVideo(job: empty) { _ in }
        }
    }

    /// Collects what the progress callback reported, from whichever thread.
    private final class Reported: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Int] = []
        func add(_ value: Int) { lock.lock(); storage.append(value); lock.unlock() }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return storage }
    }
}
