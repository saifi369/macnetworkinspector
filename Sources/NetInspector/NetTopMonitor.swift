import AppKit
import CPtySpawn
import Combine
import Darwin

/// Runs `/usr/bin/nettop` in delta mode behind a pseudo-terminal (nettop block-buffers
/// when writing to a pipe) and turns its per-process byte counters into per-app speeds.
@MainActor
final class NetTopMonitor: ObservableObject {
    @Published private(set) var apps: [AppUsage] = []
    @Published private(set) var totalDown: Double = 0
    @Published private(set) var totalUp: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastError: String?
    @Published private(set) var sampleCount = 0

    /// Sampling interval in seconds (1 or 2 keeps the UI lively without burning CPU).
    @Published var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: "interval")
            if isRunning { restart() }
        }
    }

    /// Apps with no traffic stay listed this long so the list does not jump around.
    private let idleRetention: TimeInterval = 10

    private let resolver = ProcessResolver()
    private var childPid: pid_t?
    private var exitSource: DispatchSourceProcess?
    private var masterHandle: FileHandle?
    private var pendingText = ""
    private var currentBlock: [String] = []
    private var blockIndex = 0
    private var flushTimer: Timer?
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

        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            lastError = "Could not open a pseudo-terminal (openpty failed)."
            return
        }

        guard let pid = Self.spawnNetTop(slaveFd: slave, interval: interval) else {
            lastError = "Could not launch /usr/bin/nettop: \(String(cString: strerror(errno)))"
            close(master)
            close(slave)
            return
        }
        close(slave) // parent keeps only the master side

        generation += 1
        let myGeneration = generation

        // Watch for nettop exiting (crash, permission problem, …) and restart it.
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.teardown()
                self.lastError = "nettop stopped unexpectedly. Retrying…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, !self.isRunning, !self.isPaused else { return }
                    self.start()
                }
            }
        }
        exitSource.resume()
        self.exitSource = exitSource

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.consume(text)
            }
        }

        childPid = pid
        self.masterHandle = masterHandle
        pendingText = ""
        currentBlock = []
        blockIndex = 0
        isRunning = true
    }

    func stop() {
        generation += 1
        if let pid = childPid {
            kill(pid, SIGTERM)
        }
        teardown()
    }

    private func teardown() {
        flushTimer?.invalidate()
        flushTimer = nil
        exitSource?.cancel()
        exitSource = nil
        masterHandle?.readabilityHandler = nil
        masterHandle = nil   // closing the master hangs up nettop's controlling terminal
        if let pid = childPid {
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
        }
        childPid = nil
        isRunning = false
    }

    func restart() {
        stop()
        start()
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

    func togglePause() {
        if isPaused {
            isPaused = false
            start()
        } else {
            stop()
            isPaused = true
        }
    }

    /// Spawns nettop as a session leader whose controlling terminal is our pty.
    /// That way nettop gets SIGHUP and dies whenever this app goes away, even on a hard kill.
    private static func spawnNetTop(slaveFd: Int32, interval: Int) -> pid_t? {
        let argv = [
            "/usr/bin/nettop",
            "-P", "-d", "-x", "-n",
            "-s", String(interval),
            "-L", "0",
            "-J", "bytes_in,bytes_out",
            "-t", "external",
        ]
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }
        let pid = cpty_spawn(argv[0], &cArgs, slaveFd)
        return pid > 0 ? pid : nil
    }

    // MARK: - Parsing

    private func consume(_ text: String) {
        pendingText += text
        var lines = pendingText.components(separatedBy: "\n")
        pendingText = lines.removeLast() // possibly incomplete tail

        for raw in lines {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r "))
            if line.isEmpty { continue }
            if line.hasPrefix(",bytes_in") {
                flushBlock()
                currentBlock = []
                continue
            }
            currentBlock.append(line)
        }

        // nettop writes one block per interval; flush shortly after output goes quiet so
        // we do not wait a whole interval for the next header to arrive.
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushBlock() }
        }
    }

    private func flushBlock() {
        guard !currentBlock.isEmpty else { return }
        let block = currentBlock
        currentBlock = []
        defer { blockIndex += 1 }
        // Block 0 holds cumulative counters since boot; every later block is a delta.
        guard blockIndex > 0 else { return }

        var usages: [ProcessUsage] = []
        for line in block {
            // Format: <name>.<pid>,<bytes_in>,<bytes_out>,
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let ident = fields[0]
            guard let dot = ident.lastIndex(of: "."),
                  let pid = pid_t(ident[ident.index(after: dot)...]),
                  let bytesIn = Double(fields[1]),
                  let bytesOut = Double(fields[2]) else { continue }
            let fallbackName = String(ident[..<dot])
            let info = resolver.process(for: pid, fallbackName: fallbackName)
            let seconds = Double(interval)
            usages.append(ProcessUsage(pid: pid, name: info.name, path: info.path,
                                       downBps: bytesIn / seconds, upBps: bytesOut / seconds))
        }
        publish(usages)
    }

    private func publish(_ usages: [ProcessUsage]) {
        let now = Date()
        var grouped: [pid_t: AppUsage] = [:]
        var seenPids = Set<pid_t>()

        for usage in usages {
            seenPids.insert(usage.pid)
            let info = resolver.process(for: usage.pid, fallbackName: usage.name)
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
        for (pid, app) in grouped where app.total > 0 || app.lastActive != .distantPast {
            idleApps[pid] = app
        }
        idleApps = idleApps.filter { now.timeIntervalSince($0.value.lastActive) < idleRetention }

        var result: [AppUsage] = []
        for (pid, var app) in grouped {
            if app.total == 0 && idleApps[pid] == nil { continue }
            app.processes.sort { $0.total > $1.total }
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
        resolver.prune(keepingProcesses: seenPids, keepingApps: Set(grouped.keys))
    }
}
