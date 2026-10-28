import AppKit
import SwiftUI

@main
struct NetInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var monitor = NetTopMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Turn a plain SIGTERM (pkill, logout) into a normal quit so nettop is stopped too.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source

        NetTopMonitor.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetTopMonitor.shared.stop()
    }
}

extension NetTopMonitor {
    static let shared = NetTopMonitor()
}
