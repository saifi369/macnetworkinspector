import Foundation

/// One process's traffic during the last sampling interval, as delivered by a backend.
struct RawSample {
    let pid: pid_t
    /// "Effective" pid: the process this traffic is really on behalf of (e.g. the app behind a
    /// system download helper), or 0 when it is the process itself.
    let epid: pid_t
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

/// A source of per-process traffic counters. Callbacks are delivered on the main queue.
protocol TrafficBackend: AnyObject {
    var displayName: String { get }
    func start(interval: Int,
               onSample: @escaping ([RawSample]) -> Void,
               onFailure: @escaping (String) -> Void)
    func stop()
}
