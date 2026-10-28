import Darwin
import Foundation

/// Reads per-socket byte counters straight from the kernel through the private
/// NetworkStatistics.framework, the same source nettop, Activity Monitor and iStat Menus use.
/// Event-driven and essentially free in CPU, unlike polling `nettop` (which costs >100% CPU).
/// Everything here runs on `queue`; results are handed to the main queue.
final class NetworkStatisticsBackend: TrafficBackend {
    let displayName = "NetworkStatistics"

    private typealias Ref = UnsafeMutableRawPointer
    private typealias SourceBlock = @convention(block) (Ref?, Ref?) -> Void
    private typealias DictBlock = @convention(block) (CFDictionary?) -> Void
    private typealias VoidBlock = @convention(block) () -> Void
    private typealias FnCreate = @convention(c) (CFAllocator?, DispatchQueue, @escaping SourceBlock) -> Ref?
    private typealias FnManager = @convention(c) (Ref) -> Int32
    private typealias FnDestroy = @convention(c) (Ref) -> Void
    private typealias FnSetDict = @convention(c) (Ref, @escaping DictBlock) -> Void
    private typealias FnSetVoid = @convention(c) (Ref, @escaping VoidBlock) -> Void
    private typealias FnQueryAll = @convention(c) (Ref, @escaping VoidBlock) -> Void
    private typealias FnQueryOne = @convention(c) (Ref) -> Void

    private struct API {
        let create: FnCreate
        let destroy: FnDestroy
        let addAllTCP: FnManager
        let addAllUDP: FnManager
        let setCountsBlock: FnSetDict
        let setDescriptionBlock: FnSetDict
        let setRemovedBlock: FnSetVoid
        let queryAllSources: FnQueryAll
        let queryDescription: FnQueryOne
        let keyPID: String
        let keyEPID: String
        let keyName: String
        let keyRx: String
        let keyTx: String
        let keyInterface: String
    }

    private struct Key: Hashable {
        let pid: pid_t
        let epid: pid_t
    }

    /// Static facts about a socket, delivered once by its description. The periodic counts
    /// dictionary lists pid/name keys too, but leaves them empty, so identity must come from here.
    private struct Identity {
        let pid: pid_t
        let epid: pid_t
        let name: String
        let interface: Int
    }

    private let api: API
    private let queue = DispatchQueue(label: "com.netinspector.networkstatistics")
    private let loopbackIndex = Int(if_nametoindex("lo0"))
    private var manager: Ref?
    private var timer: DispatchSourceTimer?
    private var lastCounts: [Ref: (rx: UInt64, tx: UInt64)] = [:]
    private var identities: [Ref: Identity] = [:]
    private var needsBaseline = Set<Ref>()
    private var primed = false
    private var accumulated: [Key: (name: String, rx: UInt64, tx: UInt64)] = [:]

    /// Fails (returns nil) when the framework or any symbol is missing, so callers can fall back.
    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_NOW) else {
            return nil
        }
        func fn<T>(_ name: String, _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        func key(_ name: String) -> String? {
            dlsym(handle, name).map { $0.assumingMemoryBound(to: CFString.self).pointee as String }
        }
        guard let create = fn("NStatManagerCreate", FnCreate.self),
              let destroy = fn("NStatManagerDestroy", FnDestroy.self),
              let addAllTCP = fn("NStatManagerAddAllTCP", FnManager.self),
              let addAllUDP = fn("NStatManagerAddAllUDP", FnManager.self),
              let setCountsBlock = fn("NStatSourceSetCountsBlock", FnSetDict.self),
              let setDescriptionBlock = fn("NStatSourceSetDescriptionBlock", FnSetDict.self),
              let setRemovedBlock = fn("NStatSourceSetRemovedBlock", FnSetVoid.self),
              let queryAllSources = fn("NStatManagerQueryAllSources", FnQueryAll.self),
              let queryDescription = fn("NStatSourceQueryDescription", FnQueryOne.self),
              let keyPID = key("kNStatSrcKeyPID"),
              let keyEPID = key("kNStatSrcKeyEPID"),
              let keyName = key("kNStatSrcKeyProcessName"),
              let keyRx = key("kNStatSrcKeyRxBytes"),
              let keyTx = key("kNStatSrcKeyTxBytes"),
              let keyInterface = key("kNStatSrcKeyInterface") else {
            return nil
        }
        api = API(create: create, destroy: destroy, addAllTCP: addAllTCP, addAllUDP: addAllUDP,
                  setCountsBlock: setCountsBlock, setDescriptionBlock: setDescriptionBlock,
                  setRemovedBlock: setRemovedBlock, queryAllSources: queryAllSources,
                  queryDescription: queryDescription, keyPID: keyPID, keyEPID: keyEPID, keyName: keyName,
                  keyRx: keyRx, keyTx: keyTx, keyInterface: keyInterface)
    }

    func start(interval: Int,
               onSample: @escaping ([RawSample]) -> Void,
               onFailure: @escaping (String) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            primed = false

            guard let manager = api.create(nil, queue, { [weak self] source, _ in
                guard let self, let source else { return }
                self.sourceAdded(source)
            }) else {
                DispatchQueue.main.async { onFailure("NetworkStatistics manager could not be created.") }
                return
            }
            self.manager = manager
            guard api.addAllTCP(manager) != 0, api.addAllUDP(manager) != 0 else {
                stopOnQueue()
                DispatchQueue.main.async { onFailure("NetworkStatistics refused to monitor sockets.") }
                return
            }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                guard let self, let manager = self.manager else { return }
                self.api.queryAllSources(manager) { [weak self] in
                    guard let self else { return }
                    let samples = self.accumulated.map { key, value in
                        RawSample(pid: key.pid, epid: key.epid, name: value.name, bytesIn: value.rx, bytesOut: value.tx)
                    }
                    self.accumulated.removeAll(keepingCapacity: true)
                    let wasPrimed = self.primed
                    self.primed = true
                    if wasPrimed {
                        DispatchQueue.main.async { onSample(samples) }
                    }
                }
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    // MARK: - Queue-confined internals

    private func sourceAdded(_ source: Ref) {
        // Sockets that already existed before we started report lifetime totals on their first
        // count; those must become the baseline rather than be counted as this interval's traffic.
        if !primed { needsBaseline.insert(source) }
        api.setDescriptionBlock(source) { [weak self] dict in
            guard let self, let dict = dict as? [String: Any] else { return }
            let pid = (dict[self.api.keyPID] as? pid_t) ?? 0
            self.identities[source] = Identity(
                pid: pid,
                epid: (dict[self.api.keyEPID] as? pid_t) ?? 0,
                name: (dict[self.api.keyName] as? String) ?? "",
                interface: (dict[self.api.keyInterface] as? Int) ?? 0
            )
        }
        api.setCountsBlock(source) { [weak self] dict in
            guard let self, let dict = dict as? [String: Any] else { return }
            self.countsReceived(source, dict)
        }
        api.setRemovedBlock(source) { [weak self] in
            guard let self else { return }
            self.lastCounts[source] = nil
            self.identities[source] = nil
            self.needsBaseline.remove(source)
        }
        api.queryDescription(source)
    }

    private func countsReceived(_ source: Ref, _ dict: [String: Any]) {
        let rx = (dict[api.keyRx] as? UInt64) ?? 0
        let tx = (dict[api.keyTx] as? UInt64) ?? 0
        let previous = lastCounts[source]
        lastCounts[source] = (rx, tx)

        if needsBaseline.remove(source) != nil { return }

        let deltaRx = rx >= (previous?.rx ?? 0) ? rx - (previous?.rx ?? 0) : rx
        let deltaTx = tx >= (previous?.tx ?? 0) ? tx - (previous?.tx ?? 0) : tx
        guard deltaRx > 0 || deltaTx > 0 else { return }

        // Identity comes from the description; the counts dictionary only reliably carries bytes.
        let identity = identities[source]
        let interface = identity?.interface ?? (dict[api.keyInterface] as? Int) ?? 0
        if interface == loopbackIndex { return }
        let pid = identity?.pid ?? (dict[api.keyPID] as? pid_t) ?? 0
        let epid = identity?.epid ?? 0
        let name = identity?.name ?? ""
        let key = Key(pid: pid, epid: epid == pid ? 0 : epid)
        var entry = accumulated[key] ?? (name.isEmpty ? "pid \(pid)" : name, 0, 0)
        entry.rx += deltaRx
        entry.tx += deltaTx
        accumulated[key] = entry
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        if let manager {
            api.destroy(manager)
        }
        manager = nil
        lastCounts.removeAll()
        identities.removeAll()
        needsBaseline.removeAll()
        accumulated.removeAll()
    }
}
