import AppKit
import SwiftUI

/// Renders the UI offscreen with demo data, for the README. Invoked with
/// `NetInspector --screenshots <directory>`; exits when done.
@MainActor
enum ScreenshotRenderer {
    struct RenderError: Error, CustomStringConvertible {
        let description: String
    }

    static func render(to directory: String) throws {
        let dir = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let monitor = NetTopMonitor.shared
        monitor.loadDemo(DemoData.apps)

        for (file, appearance) in [("popover-dark", NSAppearance.Name.darkAqua), ("popover-light", .aqua)] {
            let view = PopoverView(monitor: monitor)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)
            try snapshot(view, appearance: appearance, to: dir.appendingPathComponent("\(file).png"))
        }

        let bar = HStack(spacing: 18) {
            MenuBarLabel(monitor: monitor)
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
            Text("Wed 9:41")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(12)
        try snapshot(bar, appearance: .darkAqua, to: dir.appendingPathComponent("menubar-dark.png"))
    }

    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting

        // Two layout passes: the list measures its own height after the first one.
        for _ in 0..<2 {
            let size = hosting.fittingSize
            window.setContentSize(size)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }

        let size = hosting.bounds.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw RenderError(description: "Could not allocate bitmap for \(url.lastPathComponent)") }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderError(description: "Could not encode \(url.lastPathComponent)")
        }
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}
