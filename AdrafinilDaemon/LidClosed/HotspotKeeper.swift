import AdrafinilShared
import Foundation
import OSLog

/// Keeps a closed-lid Mac on the user's iPhone Personal Hotspot while an agent works (see
/// `PersonalHotspot`). Ticked on every blocking edge, lid change, and the 60s reconcile; joins
/// at most once a minute, and only when the Wi-Fi address shows the Mac is elsewhere.
///
/// One tick runs at a time, and it re-reads the wanted network after each await: a lid opened
/// while the address was being read must not trigger a join in front of the user.
@MainActor
final class HotspotKeeper {
    private let log = Logger(subsystem: AdrafinilConstants.daemonBundleID, category: "Hotspot")
    private var lastAttempt: Date?
    private var wifiDevice: String?
    /// The latest wanted network; empty means "not wanted right now".
    private var wantedName = ""
    private var ticking = false

    func tick(networkName: String) async {
        wantedName = networkName.trimmingCharacters(in: .whitespaces)
        guard !wantedName.isEmpty else {
            lastAttempt = nil
            return
        }
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }

        guard let device = await resolveWiFiDevice() else {
            log.error("No Wi-Fi interface found — can't keep the Mac on '\(self.wantedName, privacy: .public)'")
            return
        }
        let address = await CommandRunner.run("/usr/sbin/ipconfig", ["getifaddr", device], timeout: 5)
            .flatMap { $0.status == 0 ? $0.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        let name = wantedName
        guard PersonalHotspot.shouldAttemptJoin(
            networkName: name,
            onHotspot: PersonalHotspot.isHotspotAddress(address),
            lastAttempt: lastAttempt,
            now: Date(),
        ) else { return }
        lastAttempt = Date()
        log.notice("Lid closed off the hotspot (\(device, privacy: .public) address: \(address ?? "none", privacy: .public)) — joining '\(name, privacy: .public)'")
        // No password argument: macOS uses the one it already keeps for that network.
        let result = await CommandRunner.run("/usr/sbin/networksetup", ["-setairportnetwork", device, name], timeout: 30)
        let output = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "timed out"
        log.notice("networksetup -setairportnetwork exited \(result?.status ?? -1, privacy: .public): \(output.isEmpty ? "ok" : output, privacy: .public)")
    }

    private func resolveWiFiDevice() async -> String? {
        if let wifiDevice { return wifiDevice }
        guard let result = await CommandRunner.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 10),
              result.status == 0 else { return nil }
        wifiDevice = PersonalHotspot.wifiDevice(fromHardwarePorts: result.output)
        return wifiDevice
    }
}
