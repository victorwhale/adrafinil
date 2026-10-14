import AdrafinilShared
import Propofol
import SwiftUI

/// What the lid-closed extras are doing right now — Low Power Mode held for a closed lid, the
/// Mac on the iPhone hotspot, IPv6 off for it — so the menu says so instead of the Settings.
struct LidClosedStatusCard: View {
    let extras: LidClosedExtrasStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if extras.lowPowerEngaged {
                row("leaf.fill", "Low Power Mode on for the closed lid")
            }
            if extras.onPersonalHotspot {
                row("personalhotspot", extras.ipv6OffForHotspot ? "On the iPhone hotspot · IPv4 only" : "On the iPhone hotspot")
            } else if extras.ipv6OffForHotspot {
                row("network", "Wi-Fi IPv6 off, restoring")
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.awake.opacity(0.10))
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.awake)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
