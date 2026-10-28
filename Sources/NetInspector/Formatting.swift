import Foundation

enum Formatting {
    /// Formats a bytes-per-second value in the chosen unit.
    /// `compact` drops the "/s" suffix and spaces for the menu bar.
    static func rate(_ bytesPerSecond: Double, unit: SpeedUnit, compact: Bool = false) -> String {
        switch unit {
        case .bytes:
            return scale(bytesPerSecond, base: 1024,
                         suffixes: compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"],
                         compact: compact)
        case .bits:
            return scale(bytesPerSecond * 8, base: 1000,
                         suffixes: compact ? ["b", "K", "M", "G"] : ["bps", "Kbps", "Mbps", "Gbps"],
                         compact: compact)
        }
    }

    private static func scale(_ value: Double, base: Double, suffixes: [String], compact: Bool) -> String {
        var v = max(value, 0)
        var idx = 0
        while v >= base && idx < suffixes.count - 1 {
            v /= base
            idx += 1
        }
        let digits: Int
        if idx == 0 { digits = 0 }
        else if v >= 100 { digits = 0 }
        else if v >= 10 { digits = 1 }
        else { digits = compact ? 1 : 2 }
        let number = String(format: "%.\(digits)f", v)
        return compact ? "\(number)\(suffixes[idx])" : "\(number) \(suffixes[idx])"
    }
}
