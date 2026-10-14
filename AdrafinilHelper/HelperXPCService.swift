import AdrafinilShared
import Foundation
import OSLog

final class HelperXPCService: NSObject, HelperXPCProtocol, @unchecked Sendable {
    /// The process-wide blocker, shared across every connection (see `SleepBlocker`). Internally
    /// synchronized, so this service needs no lock of its own.
    private let blocker: SleepBlocker
    /// Launch-time binary identity, shared process-wide, used to adopt an in-place update.
    private let staleness: ExecutableStaleness
    private let log = Logger(subsystem: AdrafinilConstants.helperBundleID, category: "XPCService")

    init(blocker: SleepBlocker, staleness: ExecutableStaleness) {
        self.blocker = blocker
        self.staleness = staleness
        super.init()
    }

    func setSleepBlocked(_ blocked: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        log.notice("XPC setSleepBlocked(\(blocked, privacy: .public)) received from daemon")
        do {
            try blocker.set(blocked: blocked)
            reply(blocker.isBlocked, nil)
        } catch {
            log.error("XPC setSleepBlocked(\(blocked, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            reply(blocker.isBlocked, error as NSError)
        }
        // Unblocking returns us to idle — the safe point to adopt a binary an update swapped in.
        if !blocked { relaunchIfUpdated() }
    }

    func setPowerMode(_ mode: Int, onBattery: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        let source: PowerSource = onBattery ? .battery : .ac
        log.notice("XPC setPowerMode(\(mode, privacy: .public), \(source.rawValue, privacy: .public)) received from daemon")
        guard LowPowerPlan.isValidMode(mode) else {
            reply(false, NSError(
                domain: "Adrafinil.Helper.PowerMode",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "invalid power mode \(mode)"],
            ))
            return
        }
        do {
            try PMSet.run([source.pmsetFlag, "powermode", String(mode)])
            reply(true, nil)
        } catch {
            // Older macOS only knows the boolean key, which covers automatic and Low Power.
            guard mode <= LowPowerPlan.lowPowerMode,
                  (try? PMSet.run([source.pmsetFlag, "lowpowermode", String(mode)])) != nil else {
                log.error("XPC setPowerMode(\(mode, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                reply(false, error as NSError)
                return
            }
            reply(true, nil)
        }
    }

    func setWiFiIPv6Enabled(_ enabled: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        log.notice("XPC setWiFiIPv6Enabled(\(enabled, privacy: .public)) received from daemon")
        // Up to three `networksetup` runs: off the connection's queue, so a slow one never holds
        // up the sleep-block calls behind it.
        DispatchQueue.global(qos: .utility).async { [log] in
            Self.applyWiFiIPv6(enabled, log: log, reply: reply)
        }
    }

    private static func applyWiFiIPv6(_ enabled: Bool, log: Logger, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        do {
            // The service is resolved here, as root, from the system's own listings — the daemon
            // only says on or off, so no caller-supplied text ever reaches `networksetup`.
            let networksetup = "/usr/sbin/networksetup"
            let ports = try HelperTool.run(networksetup, ["-listallhardwareports"])
            guard let device = PersonalHotspot.wifiDevice(fromHardwarePorts: ports) else {
                throw NSError(domain: "Adrafinil.Helper.IPv6", code: -1, userInfo: [NSLocalizedDescriptionKey: "no Wi-Fi device"])
            }
            let order = try HelperTool.run(networksetup, ["-listnetworkserviceorder"])
            guard let service = HotspotIPv6.serviceName(forDevice: device, inServiceOrder: order) else {
                throw NSError(domain: "Adrafinil.Helper.IPv6", code: -2, userInfo: [NSLocalizedDescriptionKey: "no Wi-Fi service for \(device)"])
            }
            try HelperTool.run(networksetup, [enabled ? "-setv6automatic" : "-setv6off", service])
            reply(true, nil)
        } catch {
            log.error("XPC setWiFiIPv6Enabled(\(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error as NSError)
        }
    }

    func sleepBlockedState(reply: @escaping @Sendable (Bool) -> Void) {
        log.debug("XPC sleepBlockedState query -> \(self.blocker.isBlocked, privacy: .public)")
        reply(blocker.isBlocked)
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        reply(HelperVersion.string)
        // The daemon probes the helper's version once at startup, so a freshly relaunched (post-
        // update) daemon reaches here — the trigger that adopts a new helper binary while idle.
        relaunchIfUpdated()
    }

    /// Adopts a binary that an in-place app update swapped onto disk by exiting so `launchd`
    /// (KeepAlive) relaunches the helper from the new image. Gated on **not** currently blocking,
    /// since exiting clears the sleep block; the blocked state is re-read at the last moment so a
    /// concurrent acquire can't be dropped. A no-op unless the on-disk binary actually changed.
    private func relaunchIfUpdated() {
        guard staleness.hasBeenReplaced(), !blocker.isBlocked else { return }
        log.notice("Helper binary replaced by an update — exiting so launchd relaunches the new helper")
        exit(0)
    }
}

enum HelperVersion {
    static let string = AdrafinilConstants.marketingVersion
}
