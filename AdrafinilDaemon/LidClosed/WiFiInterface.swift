import AdrafinilShared
import Foundation

/// The Mac's Wi-Fi interface as the lid-closed extras see it: its device (cached — hardware ports
/// don't change at runtime), its IPv4 address, and its network service's IPv6 setting. Read with
/// the unprivileged system tools; changing anything goes through the helper.
@MainActor
final class WiFiInterface {
    private var cachedDevice: String?

    func device() async -> String? {
        if let cachedDevice { return cachedDevice }
        guard let result = await CommandRunner.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 10),
              result.status == 0 else { return nil }
        cachedDevice = PersonalHotspot.wifiDevice(fromHardwarePorts: result.output)
        return cachedDevice
    }

    /// The interface's IPv4 address, or nil when it has none (Wi-Fi off or not associated).
    func address() async -> String? {
        guard let device = await device(),
              let result = await CommandRunner.run("/usr/sbin/ipconfig", ["getifaddr", device], timeout: 5),
              result.status == 0 else { return nil }
        let address = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    /// The IPv6 setting of the Wi-Fi network service (renamed or not).
    func ipv6Setting() async -> IPv6Setting? {
        guard let device = await device(),
              let order = await CommandRunner.run("/usr/sbin/networksetup", ["-listnetworkserviceorder"], timeout: 10),
              order.status == 0,
              let service = HotspotIPv6.serviceName(forDevice: device, inServiceOrder: order.output),
              let info = await CommandRunner.run("/usr/sbin/networksetup", ["-getinfo", service], timeout: 10),
              info.status == 0 else { return nil }
        return HotspotIPv6.ipv6Setting(fromGetInfo: info.output)
    }
}
