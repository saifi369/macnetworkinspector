import CPtySpawn
import Darwin
import Foundation

/// Fallback backend: runs `/usr/bin/nettop` in delta mode behind a pseudo-terminal (nettop
/// block-buffers when writing to a pipe) and parses its CSV output. Works everywhere but costs
/// a lot of CPU, so it is only used when NetworkStatistics.framework is unavailable.
final class NetTopBackend: TrafficBackend {
    let displayName = "nettop (fallback, CPU heavy)"

    private var childPid: pid_t?
    private var exitSource: DispatchSourceProcess?
    private var masterHandle: FileHandle?
    private var pendingText = ""
    private var currentBlock: [String] = []
    private var blockIndex = 0
    private var flushTimer: Timer?
    private var onSample: (([RawSample]) -> Void)?

    func start(interval: Int,
               onSample: @escaping ([RawSample]) -> Void,
               onFailure: @escaping (String) -> Void) {
        stop()
        self.onSample = onSample
        pendingText = ""
        currentBlock = []
        blockIndex = 0

        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            onFailure("Could not open a pseudo-terminal (openpty failed).")
            return
        }
        guard let pid = Self.spawn(slaveFd: slave, interval: interval) else {
            close(master)
            close(slave)
            onFailure("Could not launch /usr/bin/nettop: \(String(cString: strerror(errno)))")
            return
        }
        close(slave) // parent keeps only the master side
        childPid = pid

        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        exitSource.setEventHandler { [weak self] in
            guard let self, self.childPid == pid else { return }
            self.stop()
            onFailure("nettop stopped unexpectedly.")
        }
        exitSource.resume()
        self.exitSource = exitSource

        let handle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.masterHandle === handle else { return }
                self.consume(text)
            }
        }
        masterHandle = handle
    }

    func stop() {
        flushTimer?.invalidate()
        flushTimer = nil
        exitSource?.cancel()
        exitSource = nil
        masterHandle?.readabilityHandler = nil
        masterHandle = nil   // closing the master hangs up nettop's controlling terminal
        if let pid = childPid {
            kill(pid, SIGTERM)
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
        }
        childPid = nil
    }

    /// Spawns nettop as a session leader whose controlling terminal is our pty, so it is hung up
    /// (and exits) whenever this app goes away, even after a hard kill.
    private static func spawn(slaveFd: Int32, interval: Int) -> pid_t? {
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

        // nettop writes one block per interval; flush shortly after output goes quiet so we do
        // not wait a whole interval for the next header to arrive.
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            self?.flushBlock()
        }
    }

    private func flushBlock() {
        guard !currentBlock.isEmpty else { return }
        let block = currentBlock
        currentBlock = []
        defer { blockIndex += 1 }
        // Block 0 holds cumulative counters since boot; every later block is a delta.
        guard blockIndex > 0 else { return }

        var samples: [RawSample] = []
        for line in block {
            // Format: <name>.<pid>,<bytes_in>,<bytes_out>,
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let ident = fields[0]
            guard let dot = ident.lastIndex(of: "."),
                  let pid = pid_t(ident[ident.index(after: dot)...]),
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2]) else { continue }
            samples.append(RawSample(pid: pid, epid: 0, name: String(ident[..<dot]), bytesIn: bytesIn, bytesOut: bytesOut))
        }
        onSample?(samples)
    }
}
