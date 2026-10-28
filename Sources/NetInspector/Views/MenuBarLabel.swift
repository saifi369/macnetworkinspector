import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var monitor: TrafficMonitor
    @AppStorage("menuBarMode") private var mode: MenuBarMode = .both
    @AppStorage("speedUnit") private var unit: SpeedUnit = .bytes

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: monitor.isPaused ? "pause.circle" : "arrow.up.arrow.down.circle")
            switch mode {
            case .iconOnly:
                EmptyView()
            case .download:
                Text("↓\(Formatting.rate(monitor.totalDown, unit: unit, compact: true))")
            case .both:
                Text("↓\(Formatting.rate(monitor.totalDown, unit: unit, compact: true)) ↑\(Formatting.rate(monitor.totalUp, unit: unit, compact: true))")
            }
        }
        .font(.system(size: 12).monospacedDigit())
    }
}
