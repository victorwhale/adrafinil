import Foundation

/// Keeps a closed-lid Mac on the iPhone's Personal Hotspot while an agent works. Pure.
///
/// On the move, the Mac in a bag may sit on a weak hotel network or none at all while the
/// phone's hotspot is right there. macOS redacts the current SSID for processes without Location
/// access, so "on the hotspot" is read from the Wi-Fi address instead: an iPhone Personal Hotspot
/// always hands out 172.20.10.0/28 (router 172.20.10.1). Joining reuses the password macOS
/// already keeps for that network, so nothing secret passes through Adrafinil.
public enum PersonalHotspot {
    /// Minimum spacing between join attempts, so an out-of-range phone isn't hammered.
    public static let retryInterval: TimeInterval = 60

    /// Whether `ipv4` lies in the iPhone Personal Hotspot range, 172.20.10.0/28.
    public static func isHotspotAddress(_ ipv4: String?) -> Bool {
        guard let ipv4 else { return false }
        let octets = ipv4.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 172 && octets[1] == 20 && octets[2] == 10 && octets[3] < 16
    }

    /// The Wi-Fi interface (e.g. `en0`), from `networksetup -listallhardwareports`.
    public static func wifiDevice(fromHardwarePorts output: String) -> String? {
        var inWiFiPort = false
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                let port = line.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
                inWiFiPort = port == "Wi-Fi" || port == "AirPort"
            } else if inWiFiPort, line.hasPrefix("Device:") {
                let device = line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
                return device.isEmpty ? nil : device
            }
        }
        return nil
    }

    /// Whether to try joining `networkName` now.
    public static func shouldAttemptJoin(
        networkName: String,
        onHotspot: Bool,
        lastAttempt: Date?,
        now: Date,
        retryInterval: TimeInterval = retryInterval,
    ) -> Bool {
        guard !networkName.trimmingCharacters(in: .whitespaces).isEmpty, !onHotspot else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= retryInterval
    }
}
