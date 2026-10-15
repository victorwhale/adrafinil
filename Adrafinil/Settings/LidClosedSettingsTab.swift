import AdrafinilShared
import Propofol
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

            Section {
                Toggle("Also hold busy Claude sessions a hook missed", isOn: $settings.holdBusyClaudeSessions)
            } footer: {
                Text("Claude Code's own status says which sessions are working. Every 30 seconds, one that is working but not held — a missed hook, an app restart, a pause and resume — is held again, and released by its own end hook as usual. Idle sessions are never held.")
            }

            Section {
                Toggle("Use IPv4 only on an iPhone hotspot", isOn: $settings.ipv4OnlyOnHotspot)
            } footer: {
                Text("An iPhone hotspot announces IPv6 it doesn't carry, so some apps hang until they time out. While the Mac is on one — lid open or closed — Adrafinil turns the Wi-Fi's IPv6 off, and back to automatic as soon as it leaves. A Wi-Fi you set up by hand is left alone.")
            }

            Section {
                LabeledContent("Text me when it's done") {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("Recipient", text: $recipientDraft, prompt: Text(verbatim: "+33… / you@icloud.com"))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                            .onSubmit(commitRecipient)
                        Button("Save", action: commitRecipient)
                            .disabled(!draftIsCommittable)
                    }
                }
                if !recipientDraft.isEmpty, !AwayNotice.isValidRecipient(recipientDraft) {
                    Text("Use an international number (+33…) or an email address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Phone notice")
            } footer: {
                Text("An iMessage when the agents are done behind a closed lid, or when a heat or battery cutout puts the Mac to sleep. Saving sends a first message, and macOS asks once to let Adrafinil use Messages. Empty turns it off.")
            }
        }
        .formStyle(.grouped)
        .onAppear { recipientDraft = settings.notifyRecipient }
    }

    /// Edited apart from the settings and saved only on Return or Save: saving sends a message,
    /// and a number typed digit by digit passes for valid long before it is the right one.
    @State private var recipientDraft = ""

    private var draftIsCommittable: Bool {
        recipientDraft != settings.notifyRecipient && (recipientDraft.isEmpty || AwayNotice.isValidRecipient(recipientDraft))
    }

    private func commitRecipient() {
        recipientDraft = recipientDraft.trimmingCharacters(in: .whitespaces)
        guard draftIsCommittable else { return }
        settings.notifyRecipient = recipientDraft
    }

    private var graceLabel: String {
        settings.postWorkGraceMinutes == 0
            ? String(localized: "No")
            : Duration.seconds(settings.postWorkGraceMinutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}
