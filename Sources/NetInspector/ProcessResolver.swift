import AppKit
import Darwin

/// Resolves a pid into a human-readable process and the application responsible for it.
/// Uses the same private libquarantine call that Little Snitch / LuLu use to attribute
/// helper processes (WebKit networking, Chrome helpers, XPC services, CLI tools) to their app.
final class ProcessResolver {
    struct ProcessInfo {
        let pid: pid_t
        let name: String
        let path: String
        let responsiblePid: pid_t
    }

    struct AppInfo {
        let pid: pid_t
        let name: String
        let icon: NSImage
        let bundleID: String?
        let isApplication: Bool
        let path: String
    }

    private var processCache: [pid_t: ProcessInfo] = [:]
    private var appCache: [pid_t: AppInfo] = [:]

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private let responsibleFn: ResponsibleFn? = {
        guard let handle = dlopen("/usr/lib/system/libquarantine.dylib", RTLD_NOW),
              let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    func process(for pid: pid_t, fallbackName: String) -> ProcessInfo {
        if let cached = processCache[pid] { return cached }
        let path = Self.path(for: pid)
        let name: String
        if let app = NSRunningApplication(processIdentifier: pid), let localized = app.localizedName {
            name = Self.clean(localized)
        } else if !path.isEmpty {
            name = (path as NSString).lastPathComponent
        } else {
            name = fallbackName
        }
        var responsible = pid
        if let fn = responsibleFn {
            let r = fn(pid)
            if r > 0 { responsible = r }
        }
        let info = ProcessInfo(pid: pid, name: name, path: path, responsiblePid: responsible)
        processCache[pid] = info
        return info
    }

    func app(for pid: pid_t, fallback: ProcessInfo) -> AppInfo {
        if let cached = appCache[pid] { return cached }
        let info: AppInfo
        if let running = NSRunningApplication(processIdentifier: pid),
           running.activationPolicy != .prohibited || running.bundleIdentifier != nil {
            info = AppInfo(
                pid: pid,
                name: Self.clean(running.localizedName ?? fallback.name),
                icon: running.icon ?? Self.genericIcon(path: running.executableURL?.path ?? fallback.path),
                bundleID: running.bundleIdentifier,
                isApplication: true,
                path: running.bundleURL?.path ?? running.executableURL?.path ?? fallback.path
            )
        } else {
            let path = pid == fallback.pid ? fallback.path : Self.path(for: pid)
            let name = pid == fallback.pid ? fallback.name
                : (path.isEmpty ? "pid \(pid)" : (path as NSString).lastPathComponent)
            info = AppInfo(
                pid: pid,
                name: pid == 0 ? "kernel_task" : name,
                icon: Self.genericIcon(path: path),
                bundleID: nil,
                isApplication: false,
                path: path
            )
        }
        appCache[pid] = info
        return info
    }

    /// Drop cache entries for pids that are no longer reported, so pid reuse cannot show stale names.
    func prune(keepingProcesses pids: Set<pid_t>, keepingApps appPids: Set<pid_t>) {
        processCache = processCache.filter { pids.contains($0.key) }
        appCache = appCache.filter { appPids.contains($0.key) }
    }

    /// Some apps (WhatsApp, for one) embed invisible bidi marks in their display name.
    private static func clean(_ name: String) -> String {
        name.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private static func path(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func genericIcon(path: String) -> NSImage {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
    }
}
