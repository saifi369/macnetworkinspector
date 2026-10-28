import AppKit
import Darwin

enum ProcessKiller {
    enum Outcome {
        case ok
        case failed(String)
    }

    /// Gracefully quits (SIGTERM / NSRunningApplication.terminate) or force-kills a process.
    /// Root-owned daemons are killed through an administrator prompt.
    static func terminate(pid: pid_t, name: String, force: Bool) -> Outcome {
        if let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier != nil {
            let ok = force ? app.forceTerminate() : app.terminate()
            if ok { return .ok }
            // Fall through to a plain signal if AppKit refused.
        }
        let sig = force ? SIGKILL : SIGTERM
        if kill(pid, sig) == 0 { return .ok }
        switch errno {
        case ESRCH:
            return .ok // already gone
        case EPERM:
            return killAsAdmin(pid: pid, name: name, signal: sig)
        default:
            return .failed("Could not signal \(name): \(String(cString: strerror(errno)))")
        }
    }

    private static func killAsAdmin(pid: pid_t, name: String, signal: Int32) -> Outcome {
        let script = "do shell script \"/bin/kill -\(signal) \(pid)\" with administrator privileges"
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else {
            return .failed("Could not build the admin kill script.")
        }
        apple.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 { return .failed("Cancelled.") }
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            return .failed("Admin kill of \(name) failed: \(message)")
        }
        return .ok
    }

    /// Asks the user to confirm a force-kill. Returns true when confirmed.
    static func confirmForceKill(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Force kill \(name)?"
        alert.informativeText = "The process will be stopped immediately and any unsaved work in it will be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Kill")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
