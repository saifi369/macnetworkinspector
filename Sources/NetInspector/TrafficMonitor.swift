import AppKit
import Combine

/// Owns the traffic backend, turns raw per-process samples into per-app speeds and publishes
/// them for the UI. Prefers NetworkStatistics.framework and falls back to `nettop`.
@MainActor
final class TrafficMonitor: ObservableObject {
    static let shared = TrafficMonitor()

    @Published private(set) var apps: [AppUsage] = []
    @Published private(set) var totalDown: Double = 0
    @Published private(set) var totalUp: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastError: String?
    @Published private(set) var sampleCount = 0
    @Published private(set) var backendName = ""

    /// Sampling interval in seconds.
    @Published var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: "interval")
            if isRunning { restart() }
        }
    }

    /// Apps with no traffic stay listed this long so the list does not jump around.
    private let idleRetention: TimeInterval = 10

    private let resolver = ProcessResolver()
    private var backend: TrafficBackend?
    private var preferNetTop = ProcessInfo.processInfo.environment["NETINSPECTOR_BACKEND"] == "nettop"
    private var idleApps: [pid_t: AppUsage] = [:]
    private var generation = 0

    init() {
        let saved = UserDefaults.standard.integer(forKey: "interval")
        interval = saved == 0 ? 1 : saved
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        lastError = nil
        isPaused = false
        generation += 1
        let myGeneration = generation

        let backend: TrafficBackend
        if !preferNetTop, let native = NetworkStatisticsBackend() {
            backend = native
        } else {
            backend = NetTopBackend()
        }
        self.backend = backend
        backendName = backend.displayName
        backend.start(
            interval: interval,
            onSample: { [weak self] samples in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == myGeneration else { return }
                    self.handle(samples)
                }
            },
            onFailure: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == myGeneration else { return }
                    self.handleFailure(message, from: backend)
                }
            }
        )
        isRunning = true
    }

    func stop() {
        generation += 1
        backend?.stop()
        backend = nil
        isRunning = false
    }

    func restart() {
        stop()
        start()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            start()
        } else {
            stop()
            isPaused = true
        }
    }

    /// Replaces live data with a fixed data set (used for documentation screenshots).
    func loadDemo(_ demoApps: [AppUsage]) {
        stop()
        apps = demoApps
        totalDown = demoApps.reduce(0) { $0 + $1.downBps }
        totalUp = demoApps.reduce(0) { $0 + $1.upBps }
        sampleCount = 1
        isRunning = true
    }

    private func handleFailure(_ message: String, from failed: TrafficBackend) {
        stop()
        if failed is NetworkStatisticsBackend {
            preferNetTop = true // next attempt uses nettop
        }
        lastError = "\(message) Retrying…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isRunning, !self.isPaused else { return }
            self.start()
        }
    }

    // MARK: - Aggregation

    private func handle(_ samples: [RawSample]) {
        let seconds = Double(interval)
        let usages = samples.map { sample -> ProcessUsage in
            let info = resolver.process(for: sample.pid, epid: sample.epid, fallbackName: sample.name)
            return ProcessUsage(pid: sample.pid, epid: sample.epid, name: info.name, path: info.path,
                                downBps: Double(sample.bytesIn) / seconds,
                                upBps: Double(sample.bytesOut) / seconds)
        }
        publish(usages)
    }

    private func publish(_ usages: [ProcessUsage]) {
        let now = Date()
        var grouped: [pid_t: AppUsage] = [:]
        var seenKeys = Set<ProcessResolver.Key>()

        for usage in usages {
            let key = ProcessResolver.Key(pid: usage.pid, epid: usage.epid)
            seenKeys.insert(key)
            let info = resolver.process(for: usage.pid, epid: usage.epid, fallbackName: usage.name)
            let appInfo = resolver.app(for: info.responsiblePid, fallback: info)
            var app = grouped[appInfo.pid] ?? AppUsage(
                id: appInfo.pid, name: appInfo.name, icon: appInfo.icon, bundleID: appInfo.bundleID,
                isApplication: appInfo.isApplication, path: appInfo.path,
                downBps: 0, upBps: 0, processes: [],
                lastActive: idleApps[appInfo.pid]?.lastActive ?? .distantPast
            )
            app.downBps += usage.downBps
            app.upBps += usage.upBps
            app.processes.append(usage)
            if usage.total > 0 { app.lastActive = now }
            grouped[appInfo.pid] = app
        }

        // Remember recently active apps so they linger (with zero speed) instead of vanishing.
        for (pid, app) in grouped where app.total > 0 {
            idleApps[pid] = app
        }
        idleApps = idleApps.filter { now.timeIntervalSince($0.value.lastActive) < idleRetention }

        var result: [AppUsage] = []
        for (pid, var app) in grouped {
            if app.total == 0 && idleApps[pid] == nil { continue }
            app.processes.sort { $0.total > $1.total }
            result.append(app)
        }
        // Apps that were active a moment ago but sent nothing this interval stay listed at zero.
        for (pid, var app) in idleApps where grouped[pid] == nil {
            app.downBps = 0
            app.upBps = 0
            app.processes = app.processes.map { proc in
                var p = proc
                p.downBps = 0
                p.upBps = 0
                return p
            }
            result.append(app)
        }
        result.sort {
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        apps = result
        totalDown = usages.reduce(0) { $0 + $1.downBps }
        totalUp = usages.reduce(0) { $0 + $1.upBps }
        sampleCount += 1
        resolver.prune(keepingProcesses: seenKeys, keepingApps: Set(result.map(\.id)))
    }
}
