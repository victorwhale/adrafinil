import AdrafinilShared
import Foundation
import OSLog

/// Sends the user an iMessage through Messages (see `AwayNotice`). The recipient and the text are
/// passed to the script as arguments — never spliced into its source — and the recipient must
/// pass `AwayNotice.isValidRecipient` first.
///
/// The first send asks the user once to let Adrafinil control Messages (Privacy & Security →
/// Automation); a refusal shows up here as a failed send, logged, and nothing else breaks.
@MainActor
final class IMessageNotifier {
    private let log = Logger(subsystem: AdrafinilConstants.daemonBundleID, category: "IMessage")
    private var lastWorkFinished: Date?

    private static let script = [
        "on run argv",
        "tell application \"Messages\"",
        "set targetAccount to 1st account whose service type = iMessage",
        "send (item 2 of argv) to participant (item 1 of argv) of targetAccount",
        "end tell",
        "end run",
    ]

    /// "Claude is done, the Mac sleeps in N min" — once per `AwayNotice.minInterval`.
    func workFinished(recipient: String, lidClosedAlone: Bool, agentsLeft: Int, graceMinutes: Int) async {
        let now = Date()
        guard AwayNotice.shouldNotifyWorkFinished(
            recipient: recipient,
            lidClosedAlone: lidClosedAlone,
            agentsLeft: agentsLeft,
            lastSent: lastWorkFinished,
            now: now,
        ) else { return }
        lastWorkFinished = now
        await send(AwayNotice.workFinishedText(graceMinutes: graceMinutes), to: recipient)
    }

    @discardableResult
    func send(_ text: String, to recipient: String, timeout: TimeInterval = 15) async -> Bool {
        guard AwayNotice.isValidRecipient(recipient) else { return false }
        let arguments = Self.script.flatMap { ["-e", $0] } + [recipient, text]
        let result = await CommandRunner.run("/usr/bin/osascript", arguments, timeout: timeout)
        guard let result, result.status == 0 else {
            // The AppleScript error can quote the recipient: kept out of the public log.
            let detail = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "timed out"
            log.error("iMessage not sent: \(detail, privacy: .private)")
            return false
        }
        log.notice("iMessage sent")
        return true
    }
}
