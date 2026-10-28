import AppKit

/// Traffic of one OS process, as reported by `nettop`.
struct ProcessUsage: Identifiable, Equatable {
    let pid: pid_t
    /// Process this traffic is on behalf of (0 = itself). One helper can serve several apps.
    let epid: pid_t
    let name: String
    let path: String
    var downBps: Double   // bytes per second
    var upBps: Double

    var id: String { "\(pid)/\(epid)" }
    var total: Double { downBps + upBps }

    static func == (lhs: ProcessUsage, rhs: ProcessUsage) -> Bool {
        lhs.id == rhs.id && lhs.downBps == rhs.downBps && lhs.upBps == rhs.upBps
    }
}

/// Traffic of an application: the "responsible" process plus every helper
/// process it spawned (browser helpers, XPC services, CLI tools under a terminal…).
struct AppUsage: Identifiable {
    let id: pid_t              // pid of the responsible process
    let name: String
    let icon: NSImage
    let bundleID: String?
    let isApplication: Bool    // true when it is a regular GUI app (NSRunningApplication)
    let path: String
    var downBps: Double
    var upBps: Double
    var processes: [ProcessUsage]
    var lastActive: Date

    var total: Double { downBps + upBps }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case bytes, bits
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bytes: return "MB/s"
        case .bits:  return "Mbps"
        }
    }
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case iconOnly, download, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .download: return "Download speed"
        case .both:     return "Download + upload"
        }
    }
}
