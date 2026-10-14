import AdrafinilShared
import Foundation
import Network
import OSLog

/// IPv4 only while the Mac is on the iPhone Personal Hotspot (see `HotspotIPv6`), lid open or
/// closed: the hotspot's unrouted IPv6 stalls clients whatever the lid does. Event-driven — a
/// network path monitor re-evaluates on every network change, so there is no polling — and also
/// re-evaluated on settings reloads.
///
/// "Switched off by us" is persisted (a marker file) before anything relies on it, so a crash or
/// reboot on the hotspot still restores automatic IPv6 once the Mac is elsewhere. A Wi-Fi that is
/// merely between networks (no address) is left alone, so a brief drop doesn't flap the setting.
@MainActor
final class HotspotIPv6Keeper {
    private let log = Logger(subsystem: AdrafinilConstants.daemonBundleID, category: "HotspotIPv6")
    private let helperClient: HelperClient
    private let wifi: WiFiInterface
    private let markerURL: URL
    private var monitor: NWPathMonitor?
    private var pending: Task<Void, Never>?

    /// Called after each evaluation, so the daemon can push the new state to the menu.
    var onChange: (() -> Void)?

    /// Whether the Wi-Fi address was in the iPhone hotspot range at the last evaluation.
    private(set) var onHotspot = false
    /// Whether the Wi-Fi service's IPv6 is currently switched off by this keeper.
    private(set) var isOffForHotspot: Bool

    init(
        helperClient: HelperClient,
        wifi: WiFiInterface,
        markerURL: URL = AdrafinilConstants.appSupportURL.appendingPathComponent("ipv6-off-for-hotspot"),
    ) {
        self.helperClient = helperClient
        self.wifi = wifi
        self.markerURL = markerURL
        isOffForHotspot = FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Starts watching network changes. `enabled` is read at each change, so a settings reload
    /// needs no restart.
    func start(enabled: @escaping @MainActor () -> Bool) {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.update(enabled: enabled())
            }
        }
        monitor.start(queue: DispatchQueue(label: "glass.kagerou.adrafinil.daemon.ipv6"))
        self.monitor = monitor
    }

    /// Re-evaluates now. Serialized: a change landing mid-evaluation runs after it.
    func update(enabled: Bool) async {
        let previous = pending
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.apply(enabled: enabled)
        }
        pending = task
        await task.value
    }

    private func apply(enabled: Bool) async {
        let address = await wifi.address()
        onHotspot = PersonalHotspot.isHotspotAddress(address)
        defer { onChange?() }
        // Between networks: nothing to decide until the Wi-Fi lands somewhere.
        guard address != nil || !enabled else { return }
        let current = (enabled && onHotspot) || isOffForHotspot ? await wifi.ipv6Setting() : nil
        switch HotspotIPv6.action(enabled: enabled, onHotspot: onHotspot, turnedOffByUs: isOffForHotspot, current: current) {
        case .turnOff:
            // The marker stays even if the call fails: a timed-out call may still have applied,
            // and the restore re-reads the setting before it puts anything back.
            setMarker(true)
            if await helperClient.setWiFiIPv6Enabled(false) {
                log.notice("On the iPhone hotspot — Wi-Fi IPv6 switched off (IPv4 only)")
            } else {
                log.error("Could not confirm Wi-Fi IPv6 off on the hotspot")
            }
        case .restore:
            if await helperClient.setWiFiIPv6Enabled(true) {
                setMarker(false)
                log.notice("Off the iPhone hotspot (or setting off) — Wi-Fi IPv6 back to automatic")
            } else {
                log.error("Could not restore Wi-Fi IPv6 — retrying on the next network change")
            }
        case .forget:
            setMarker(false)
            log.notice("Wi-Fi IPv6 was changed by hand since — left as it is")
        case .none:
            break
        }
    }

    private func setMarker(_ on: Bool) {
        isOffForHotspot = on
        if on {
            FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: markerURL)
        }
    }
}
