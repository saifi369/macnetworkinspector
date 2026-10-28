import SwiftUI

struct AppRow: View {
    let app: AppUsage
    let unit: SpeedUnit
    let share: Double           // 0...1, this app's traffic relative to the busiest app
    let onNotice: (String) -> Void

    @State private var expanded = false

    private var hasDetails: Bool {
        app.processes.count > 1 || app.processes.first?.pid != app.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hasDetails ? 1 : 0)
                .disabled(!hasDetails)

                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(app.path)

                Spacer(minLength: 6)

                SpeedColumn(down: app.downBps, up: app.upBps, unit: unit)

                KillButtons(pid: app.id, name: app.name, onNotice: onNotice)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: geo.size.width * share, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }

            if expanded && hasDetails {
                VStack(spacing: 0) {
                    ForEach(app.processes) { proc in
                        ProcessRow(process: proc, unit: unit, onNotice: onNotice)
                    }
                }
                .padding(.leading, 50)
                .padding(.bottom, 4)
            }
        }
    }

    private var subtitle: String {
        let count = app.processes.count
        if count == 1, let proc = app.processes.first, proc.pid == app.id {
            return "pid \(proc.pid)"
        }
        return "\(count) process\(count == 1 ? "" : "es")"
    }
}

struct ProcessRow: View {
    let process: ProcessUsage
    let unit: SpeedUnit
    let onNotice: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(process.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text("pid \(process.pid)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .help(process.path)
            Spacer(minLength: 6)
            SpeedColumn(down: process.downBps, up: process.upBps, unit: unit, small: true)
            KillButtons(pid: process.pid, name: process.name, onNotice: onNotice, small: true)
        }
        .padding(.trailing, 14)
        .padding(.vertical, 3)
    }
}

struct SpeedColumn: View {
    let down: Double
    let up: Double
    let unit: SpeedUnit
    var small = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("↓ " + Formatting.rate(down, unit: unit))
                .foregroundStyle(down > 0 ? Color.blue : Color.secondary)
            Text("↑ " + Formatting.rate(up, unit: unit))
                .foregroundStyle(up > 0 ? Color.orange : Color.secondary)
        }
        .font(.system(size: small ? 10 : 11, weight: .medium).monospacedDigit())
        .frame(width: 88, alignment: .trailing)
    }
}

struct KillButtons: View {
    let pid: pid_t
    let name: String
    let onNotice: (String) -> Void
    var small = false

    var body: some View {
        HStack(spacing: 4) {
            Button("Quit") {
                report(ProcessKiller.terminate(pid: pid, name: name, force: false))
            }
            .help("Ask \(name) to quit")

            Button {
                guard ProcessKiller.confirmForceKill(name: name) else { return }
                report(ProcessKiller.terminate(pid: pid, name: name, force: true))
            } label: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            .help("Force kill \(name)")
        }
        .buttonStyle(.bordered)
        .controlSize(small ? .mini : .small)
    }

    private func report(_ outcome: ProcessKiller.Outcome) {
        if case .failed(let message) = outcome { onNotice(message) }
    }
}
