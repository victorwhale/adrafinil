import Testing
@testable import AdrafinilShared

/// IPv4 only on the iPhone hotspot: the hotspot advertises IPv6 it doesn't route, so clients that
/// try IPv6 first stall. The Wi-Fi service's IPv6 is switched off while on the hotspot and put
/// back to automatic on leaving it — and never touched when the user set it up otherwise.
@Suite("HotspotIPv6")
struct HotspotIPv6Tests {
    private let serviceOrder = """
    An asterisk (*) denotes that a network service is disabled.
    (1) USB 10/100/1000 LAN
    (Hardware Port: USB 10/100/1000 LAN, Device: en5)
    
    (2) Wi-Fi maison
    (Hardware Port: Wi-Fi, Device: en0)
    
    (*) Thunderbolt Bridge
    (Hardware Port: Thunderbolt Bridge, Device: bridge0)
    """

    @Test
    func `finds the network service of a device, even when renamed`() {
        #expect(HotspotIPv6.serviceName(forDevice: "en0", inServiceOrder: serviceOrder) == "Wi-Fi maison")
        #expect(HotspotIPv6.serviceName(forDevice: "en5", inServiceOrder: serviceOrder) == "USB 10/100/1000 LAN")
    }

    @Test
    func `a disabled service or an unknown device yields nothing`() {
        #expect(HotspotIPv6.serviceName(forDevice: "bridge0", inServiceOrder: serviceOrder) == nil)
        #expect(HotspotIPv6.serviceName(forDevice: "en9", inServiceOrder: serviceOrder) == nil)
    }

    @Test
    func `reads the IPv6 setting from networksetup -getinfo`() {
        #expect(HotspotIPv6.ipv6Setting(fromGetInfo: "DHCP Configuration\nIP address: 172.20.10.12\nIPv6: Automatic\nIPv6 IP address: none\n") == .automatic)
        #expect(HotspotIPv6.ipv6Setting(fromGetInfo: "DHCP Configuration\nIPv6: Off\n") == .off)
        #expect(HotspotIPv6.ipv6Setting(fromGetInfo: "IPv6: Manual\n") == .other("Manual"))
        #expect(HotspotIPv6.ipv6Setting(fromGetInfo: "garbage") == nil)
    }

    @Test
    func `on the hotspot, automatic IPv6 is switched off`() {
        #expect(HotspotIPv6.action(enabled: true, onHotspot: true, turnedOffByUs: false, current: .automatic) == .turnOff)
    }

    @Test
    func `nothing to do when already off, or set up by hand, or unknown`() {
        #expect(HotspotIPv6.action(enabled: true, onHotspot: true, turnedOffByUs: true, current: .off) == HotspotIPv6.Action.none)
        #expect(HotspotIPv6.action(enabled: true, onHotspot: true, turnedOffByUs: false, current: .off) == HotspotIPv6.Action.none)
        #expect(HotspotIPv6.action(enabled: true, onHotspot: true, turnedOffByUs: false, current: .other("Manual")) == HotspotIPv6.Action.none)
        #expect(HotspotIPv6.action(enabled: true, onHotspot: true, turnedOffByUs: false, current: nil) == HotspotIPv6.Action.none)
    }

    @Test
    func `leaving the hotspot, or turning the setting off, restores only what we switched`() {
        #expect(HotspotIPv6.action(enabled: true, onHotspot: false, turnedOffByUs: true, current: .off) == .restore)
        #expect(HotspotIPv6.action(enabled: false, onHotspot: true, turnedOffByUs: true, current: .off) == .restore)
        #expect(HotspotIPv6.action(enabled: true, onHotspot: false, turnedOffByUs: false, current: .off) == HotspotIPv6.Action.none)
    }

    @Test
    func `a setting changed by hand since we switched it is left alone and forgotten`() {
        #expect(HotspotIPv6.action(enabled: true, onHotspot: false, turnedOffByUs: true, current: .automatic) == .forget)
        #expect(HotspotIPv6.action(enabled: false, onHotspot: false, turnedOffByUs: true, current: .other("Manual")) == .forget)
    }

    @Test
    func `an unreadable setting is retried later rather than guessed`() {
        #expect(HotspotIPv6.action(enabled: true, onHotspot: false, turnedOffByUs: true, current: nil) == HotspotIPv6.Action.none)
    }

    @Test
    func `a service name that could pass for an option, or carries control characters, is refused`() {
        let hostile = "(1) -setv6off\n(Hardware Port: Wi-Fi, Device: en0)\n"
        #expect(HotspotIPv6.serviceName(forDevice: "en0", inServiceOrder: hostile) == nil)
        let control = "(1) Wi\u{7}Fi\n(Hardware Port: Wi-Fi, Device: en0)\n"
        #expect(HotspotIPv6.serviceName(forDevice: "en0", inServiceOrder: control) == nil)
    }
}
