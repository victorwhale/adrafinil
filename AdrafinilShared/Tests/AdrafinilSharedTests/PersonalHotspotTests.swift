import Foundation
import Testing
@testable import AdrafinilShared

/// Keeping a closed-lid Mac on the iPhone's Personal Hotspot. macOS hides the current SSID from
/// apps without Location access, so being on the hotspot is read from the address instead: an
/// iPhone hotspot always hands out 172.20.10.0/28.
@Suite("PersonalHotspot")
struct PersonalHotspotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ["172.20.10.2", "172.20.10.12", "172.20.10.14"])
    func `addresses inside the iPhone hotspot range`(address: String) {
        #expect(PersonalHotspot.isHotspotAddress(address))
    }

    @Test(arguments: ["172.20.10.17", "172.20.1.12", "192.168.1.20", "10.0.0.2", "", "not an ip"])
    func `addresses outside it`(address: String) {
        #expect(!PersonalHotspot.isHotspotAddress(address))
    }

    @Test
    func `no address is not the hotspot`() {
        #expect(!PersonalHotspot.isHotspotAddress(nil))
    }

    @Test
    func `finds the Wi-Fi device among the hardware ports`() {
        let output = """
        
        Hardware Port: Ethernet Adapter (en3)
        Device: en3
        Ethernet Address: 16:21:25:43:8e:a5
        
        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: c0:c7:db:04:d8:9e
        """
        #expect(PersonalHotspot.wifiDevice(fromHardwarePorts: output) == "en0")
    }

    @Test
    func `no Wi-Fi port yields nil`() {
        #expect(PersonalHotspot.wifiDevice(fromHardwarePorts: "Hardware Port: Thunderbolt Bridge\nDevice: bridge0\n") == nil)
    }

    @Test
    func `joins when away from the hotspot and no attempt is recent`() {
        #expect(PersonalHotspot.shouldAttemptJoin(networkName: "iPhone du V", onHotspot: false, lastAttempt: nil, now: now))
        let old = now.addingTimeInterval(-61)
        #expect(PersonalHotspot.shouldAttemptJoin(networkName: "iPhone du V", onHotspot: false, lastAttempt: old, now: now))
    }

    @Test
    func `does nothing when already on it, turned off, or just tried`() {
        #expect(!PersonalHotspot.shouldAttemptJoin(networkName: "iPhone du V", onHotspot: true, lastAttempt: nil, now: now))
        #expect(!PersonalHotspot.shouldAttemptJoin(networkName: "  ", onHotspot: false, lastAttempt: nil, now: now))
        let recent = now.addingTimeInterval(-20)
        #expect(!PersonalHotspot.shouldAttemptJoin(networkName: "iPhone du V", onHotspot: false, lastAttempt: recent, now: now))
    }
}
