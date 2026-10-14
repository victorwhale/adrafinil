import Foundation

/// A network service's IPv6 configuration, as `networksetup -getinfo` reports it.
public enum IPv6Setting: Equatable, Sendable {
    case automatic
    case off
    /// Manual, link-local only, … — set up by hand, so never touched.
    case other(String)
}

/// IPv4 only while on the iPhone Personal Hotspot. Pure.
///
/// The hotspot advertises IPv6 it doesn't route: clients that try IPv6 first (Python's httplib2,
/// for one) stall until they time out, while IPv4 answers at once. Switching the Wi-Fi service's
/// IPv6 off while on the hotspot — and back to automatic on leaving it — fixes every client at
/// once. Only an automatic setting is switched, and only one this feature switched is restored:
/// a configuration the user made by hand is never touched.
public enum HotspotIPv6 {
    public enum Action: Equatable, Sendable {
        case turnOff
        case restore
        /// We switched it, but it no longer reads off: someone changed it by hand since. Leave
        /// it as it is and drop our marker.
        case forget
        case none
    }

    /// The network service of `device` (e.g. `en0` → "Wi-Fi", or whatever the user renamed it),
    /// from `networksetup -listnetworkserviceorder`. Disabled services (`(*)`) are skipped.
    public static func serviceName(forDevice device: String, inServiceOrder output: String) -> String? {
        var pendingName: String?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("(Hardware Port:") {
                if line.hasSuffix("Device: \(device))"), let name = pendingName { return name }
                pendingName = nil
            } else if line.hasPrefix("("), let close = line.firstIndex(of: ")") {
                let marker = line[line.index(after: line.startIndex) ..< close]
                let name = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
                // A name that could pass for an option, or carries control characters, is never
                // handed to `networksetup` (which the helper runs as root).
                let usable = !name.isEmpty && !name.hasPrefix("-") && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
                pendingName = marker.allSatisfy(\.isNumber) && !marker.isEmpty && usable ? name : nil
            }
        }
        return nil
    }

    /// The `IPv6:` line of `networksetup -getinfo <service>`.
    public static func ipv6Setting(fromGetInfo output: String) -> IPv6Setting? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("IPv6:") else { continue }
            let value = line.dropFirst("IPv6:".count).trimmingCharacters(in: .whitespaces)
            switch value {
            case "Automatic": return .automatic
            case "Off": return .off
            default: return value.isEmpty ? nil : .other(value)
            }
        }
        return nil
    }

    /// `current` must be read whenever we're on the hotspot with the setting on, or hold a switch
    /// to undo: a restore only puts back what still reads off.
    public static func action(enabled: Bool, onHotspot: Bool, turnedOffByUs: Bool, current: IPv6Setting?) -> Action {
        if enabled, onHotspot {
            return current == .automatic ? .turnOff : .none
        }
        guard turnedOffByUs, let current else { return .none }
        return current == .off ? .restore : .forget
    }
}
