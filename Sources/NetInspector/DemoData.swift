import AppKit

/// Synthetic data used by `--screenshots` so documentation images never contain real user activity.
/// Only Apple's own bundled apps are referenced.
enum DemoData {
    static var apps: [AppUsage] {
        let kb = 1024.0
        let mb = kb * 1024
        return [
            app(pid: 501, bundleID: "com.apple.Safari", name: "Safari", down: 12.4 * mb, up: 210 * kb, processes: [
                ("Safari Networking", 503, 12.3 * mb, 204 * kb),
                ("Safari Web Content", 507, 96 * kb, 6 * kb),
            ]),
            app(pid: 612, bundleID: "com.apple.AppStore", name: "App Store", down: 8.1 * mb, up: 32 * kb, processes: [
                ("appstoreagent", 615, 8.1 * mb, 32 * kb),
            ]),
            app(pid: 733, bundleID: "com.apple.Music", name: "Music", down: 1.2 * mb, up: 4 * kb, processes: [
                ("Music", 733, 1.2 * mb, 4 * kb),
            ]),
            app(pid: 801, bundleID: "com.apple.Terminal", name: "Terminal", down: 640 * kb, up: 12 * kb, processes: [
                ("curl", 844, 640 * kb, 12 * kb),
            ]),
            app(pid: 920, bundleID: "com.apple.mail", name: "Mail", down: 42 * kb, up: 18 * kb, processes: [
                ("Mail", 920, 42 * kb, 18 * kb),
            ]),
            app(pid: 239, bundleID: nil, name: "mDNSResponder", down: 1.1 * kb, up: 0.6 * kb, processes: [
                ("mDNSResponder", 239, 1.1 * kb, 0.6 * kb),
            ]),
        ]
    }

    private static func app(pid: pid_t, bundleID: String?, name: String, down: Double, up: Double,
                            processes: [(String, pid_t, Double, Double)]) -> AppUsage {
        let icon: NSImage
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
        }
        return AppUsage(
            id: pid, name: name, icon: icon, bundleID: bundleID, isApplication: bundleID != nil,
            path: "", downBps: down, upBps: up,
            processes: processes.map { ProcessUsage(pid: $0.1, name: $0.0, path: "", downBps: $0.2, upBps: $0.3) },
            lastActive: Date()
        )
    }
}
