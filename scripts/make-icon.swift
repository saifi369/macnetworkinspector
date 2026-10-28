// Renders a simple app icon (gradient tile + up/down arrows) and writes AppIcon.icns.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = size * 0.1
let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
                        xRadius: size * 0.18, yRadius: size * 0.18)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.80, alpha: 1),
])!
gradient.draw(in: tile, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let rect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: rect)
    rect.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let drawRect = NSRect(x: (size - symbol.size.width) / 2, y: (size - symbol.size.height) / 2,
                          width: symbol.size.width, height: symbol.size.height)
    tinted.draw(in: drawRect)
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = "\(outDir)/icon_master.png"
try! png.write(to: URL(fileURLWithPath: master))

func run(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
}
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let name = px == 1024 ? "icon_512x512@2x.png" : "icon_\(px)x\(px).png"
    run(["sips", "-z", "\(px)", "\(px)", master, "--out", "\(iconset)/\(name)"])
    if px >= 32 && px < 1024 {
        run(["sips", "-z", "\(px)", "\(px)", master, "--out", "\(iconset)/icon_\(px / 2)x\(px / 2)@2x.png"])
    }
}
run(["iconutil", "-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"])
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.removeItem(atPath: master)
print("wrote \(outDir)/AppIcon.icns")
