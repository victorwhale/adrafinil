import Foundation

/// XPC interface exposed by AdrafinilHelper: toggle sleep blocking, set a power source's energy
/// mode for Low Power Mode while the lid is closed (see `LowPowerPlan`), and switch the Wi-Fi
/// service's IPv6 for IPv4 only on the iPhone hotspot (see `HotspotIPv6`).
/// Reply closures are `@Sendable`: NSXPC delivers them on its own private queue, so they
/// must not be `@MainActor`-isolated (which would trap when the reply fires off the main actor).
@objc
public protocol HelperXPCProtocol {
    /// Block (true) or unblock (false) system sleep, including clamshell sleep.
    /// Idempotent. Returns the actual resulting state.
    func setSleepBlocked(_ blocked: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void)

    /// Current sleep-blocking state as seen by the helper.
    func sleepBlockedState(reply: @escaping @Sendable (Bool) -> Void)

    /// Set one power source's energy mode (`pmset -b|-c powermode`): 0 automatic, 1 Low Power,
    /// 2 High Power. Any other value is refused. Returns whether the mode was applied.
    func setPowerMode(_ mode: Int, onBattery: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void)

    /// Switch the Wi-Fi service's IPv6 off (false) or back to automatic (true), for IPv4 only on
    /// the iPhone hotspot (see `HotspotIPv6`). The helper finds the Wi-Fi service itself; nothing
    /// but this flag crosses the boundary. Returns whether it applied.
    func setWiFiIPv6Enabled(_ enabled: Bool, reply: @escaping @Sendable (Bool, NSError?) -> Void)

    /// Helper version string.
    func version(reply: @escaping @Sendable (String) -> Void)
}
