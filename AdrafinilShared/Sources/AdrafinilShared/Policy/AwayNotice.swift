import Foundation

/// A phone notice — an SMS through a notification command, or an iMessage to the user — when work
/// behind a closed lid ends or is cut off, so someone with the Mac in a bag knows when to open it
/// again. Pure: the daemon decides with this, then sends.
public enum AwayNotice {
    /// At most one "work finished" notice per window: agents finishing one after another, or a
    /// grace re-armed by a quick follow-up, must not turn into a string of texts.
    public static let minInterval: TimeInterval = 10 * 60

    /// An E.164 phone number or a plain email address — the two handles Messages accepts. Strict,
    /// since the value is handed to Messages as the recipient.
    public static func isValidRecipient(_ recipient: String) -> Bool {
        if recipient.hasPrefix("+") {
            let digits = recipient.dropFirst()
            return (8 ... 15).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
        }
        let parts = recipient.split(separator: "@", omittingEmptySubsequences: false)
        // First character alphanumeric: a leading "-" could pass for an option on a command line.
        guard parts.count == 2, let first = parts[0].unicodeScalars.first,
              first.isASCII, CharacterSet.alphanumerics.contains(first), parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_+"))
        return recipient.unicodeScalars.allSatisfy { $0.isASCII && (allowed.contains($0) || $0 == "@") }
    }

    /// A notification command (an SMS sender, for one) the daemon may run: an absolute path with no
    /// `.` or `..` component and no control characters. The daemon also checks the file itself
    /// (owned by the user, executable, not writable by others) before running it.
    public static func isPlausibleCommandPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Whether a notice has somewhere to go: a notification command, or an iMessage recipient.
    public static func hasChannel(recipient: String, command: String) -> Bool {
        isPlausibleCommandPath(command) || isValidRecipient(recipient)
    }

    public static func shouldNotifyWorkFinished(
        recipient: String,
        command: String = "",
        lidClosedAlone: Bool,
        agentsLeft: Int,
        lastSent: Date?,
        now: Date,
    ) -> Bool {
        guard hasChannel(recipient: recipient, command: command), lidClosedAlone, agentsLeft == 0 else { return false }
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= minInterval
    }

    /// Sent once when a recipient is set: proves the route, and raises the Messages permission
    /// prompt while the user is at the Mac.
    public static let confirmationText = "Adrafinil : les alertes du Mac arriveront ici."

    public static func workFinishedText(graceMinutes: Int) -> String {
        graceMinutes > 0
            ? "Adrafinil : Claude a fini. Le Mac se met en veille dans \(graceMinutes) min."
            : "Adrafinil : Claude a fini. Le Mac se met en veille."
    }

    public static func thermalCutoutText(celsius: Double?) -> String {
        guard let celsius else { return "Adrafinil : coupure, trop chaud. Le Mac se met en veille." }
        return "Adrafinil : coupure à \(Int(celsius.rounded())) °C, trop chaud. Le Mac se met en veille."
    }

    public static func lowBatteryCutoutText(percent: Int?) -> String {
        guard let percent else { return "Adrafinil : batterie faible. Le Mac se met en veille." }
        return "Adrafinil : batterie à \(percent) %. Le Mac se met en veille."
    }
}
