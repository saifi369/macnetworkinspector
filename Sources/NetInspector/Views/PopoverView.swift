import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: NetTopMonitor
    @AppStorage("speedUnit") private var unit: SpeedUnit = .bytes
    @AppStorage("menuBarMode") private var menuBarMode: MenuBarMode = .both
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var listHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let notice {
                Divider()
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .frame(width: 420)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Formatting.rate(monitor.totalDown, unit: unit))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Upload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Formatting.rate(monitor.totalUp, unit: unit))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                monitor.togglePause()
            } label: {
                Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .help(monitor.isPaused ? "Resume monitoring" : "Pause monitoring")

            Menu {
                Picker("Units", selection: $unit) {
                    ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                }
                Picker("Menu bar", selection: $menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Refresh every", selection: $monitor.interval) {
                    Text("1 second").tag(1)
                    Text("2 seconds").tag(2)
                    Text("5 seconds").tag(5)
                }
                Divider()
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = monitor.lastError, monitor.apps.isEmpty {
            placeholder(symbol: "exclamationmark.triangle", text: error)
        } else if monitor.isPaused {
            placeholder(symbol: "pause.circle", text: "Monitoring paused")
        } else if monitor.apps.isEmpty {
            placeholder(symbol: monitor.sampleCount == 0 ? "antenna.radiowaves.left.and.right" : "moon.zzz",
                        text: monitor.sampleCount == 0 ? "Measuring…" : "No network activity")
        } else {
            let maxTotal = monitor.apps.map(\.total).max() ?? 1
            // A ScrollView inside a menu bar window has no intrinsic height, so measure the
            // rows and size the scroll area to them (capped, so long lists scroll).
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(monitor.apps) { app in
                        AppRow(app: app, unit: unit, share: maxTotal > 0 ? app.total / maxTotal : 0,
                               onNotice: show(notice:))
                        Divider().padding(.leading, 14)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(max(listHeight, 44), maxListHeight))
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(monitor.apps.isEmpty ? "" : "\(monitor.apps.count) apps using the network")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit Net Inspector") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { notice = nil }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            show(notice: "Launch at login failed: \(error.localizedDescription). Move the app to /Applications and try again.")
        }
    }
}
