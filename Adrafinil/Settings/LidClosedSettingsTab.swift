import AdrafinilShared
import SwiftUI

// MARK: - Lid Closed tab

/// What happens around work done behind a closed lid: how long the Mac stays up once the agents
/// finish, whether it then goes to sleep on its own, and how it saves power and stays online on
/// the move meanwhile.
struct LidClosedSettingsTab: View {
    @Binding var settings: AdrafinilSettings

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.postWorkGraceMinutes, in: 0 ... 60) {
                    LabeledContent("Stay awake after the work ends", value: graceLabel)
                }
                Toggle("Then put the Mac to sleep if the lid is closed", isOn: $settings.sleepWhenWorkEnds)
            } header: {
                Text("When the work is done")
            } footer: {
                Text("The grace period leaves time for a follow-up — at the keyboard or from your phone — before the Mac sleeps; the menu shows its countdown. macOS only sleeps a closed lid at the moment it closes, so a Mac kept awake past that moment needs Adrafinil to put it to sleep afterwards. Not with an external display connected.")
            }

            Section {
                Toggle("Use Low Power Mode", isOn: $settings.lowPowerWhileLidClosed)
                LabeledContent("Stay on this iPhone hotspot") {
                    TextField("Hotspot name", text: $settings.hotspotNetworkName, prompt: Text("Off"))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            } header: {
                Text("While an agent works with the lid closed")
            } footer: {
                Text("Low Power Mode cuts heat and drain in a bag; each power source gets its own mode back afterwards. The hotspot name is your iPhone's name as it appears in the Wi-Fi menu: if the Mac isn't on that hotspot, Adrafinil joins it, using the password macOS already knows. Keep \"Allow Others to Join\" on in the iPhone's Personal Hotspot settings so the Mac can find it. Neither applies with an external display connected.")
            }
        }
        .formStyle(.grouped)
    }

    private var graceLabel: String {
        settings.postWorkGraceMinutes == 0
            ? String(localized: "No")
            : Duration.seconds(settings.postWorkGraceMinutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}
