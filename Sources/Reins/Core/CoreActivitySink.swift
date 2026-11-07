import Foundation

/// One `activitySubscribe` stream's end of the pipe. The snapshot a subscribe returns must reach the stream before any
/// `activity/report` push that follows it, but the reader thread may deliver the push before the awaiting task has resumed
/// with the snapshot. Pushes wait here until the snapshot is out (only the newest matters: a report replaces the whole).
final class CoreActivitySink: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<CoreActivityReport, Error>.Continuation
    private let lock = NSLock()
    private var held: CoreActivityReport?
    private var live = false

    init(_ continuation: AsyncThrowingStream<CoreActivityReport, Error>.Continuation) {
        self.continuation = continuation
    }

    /// A new subscription starts; hold pushes until its snapshot is delivered.
    func reset() {
        lock.withLock {
            live = false
            held = nil
        }
    }

    func push(_ report: CoreActivityReport) {
        lock.withLock {
            if live { continuation.yield(report) } else { held = report }
        }
    }

    func deliver(_ snapshot: CoreActivityReport) {
        lock.withLock {
            continuation.yield(snapshot)
            if let held { continuation.yield(held) }
            held = nil
            live = true
        }
    }

    func finish(throwing error: Error? = nil) {
        continuation.finish(throwing: error)
    }
}
