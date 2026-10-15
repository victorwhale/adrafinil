import AdrafinilShared
import Darwin
import Foundation
import OSLog

/// Sends the user a phone notice (see `AwayNotice`): through the notification command first — an SMS
/// sender, run with the text as its only argument — then, if that's unset or fails, as an iMessage
/// through Messages. Neither the recipient nor the text is ever spliced into a script or a shell.
///
/// The command must be an absolute path to a regular file the user owns, can execute, and nobody
/// else can modify. The first iMessage asks the user once to let Adrafinil control Messages
/// (Privacy & Security → Automation); a refusal shows up here as a failed send, logged.
@MainActor
final class PhoneNotifier {
    private let log = Logger(subsystem: AdrafinilConstants.daemonBundleID, category: "PhoneNotice")
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
    func workFinished(recipient: String, command: String, lidClosedAlone: Bool, agentsLeft: Int, graceMinutes: Int) async {
        let now = Date()
        guard AwayNotice.shouldNotifyWorkFinished(
            recipient: recipient,
            command: command,
            lidClosedAlone: lidClosedAlone,
            agentsLeft: agentsLeft,
            lastSent: lastWorkFinished,
            now: now,
        ) else { return }
        lastWorkFinished = now
        await send(AwayNotice.workFinishedText(graceMinutes: graceMinutes), recipient: recipient, command: command)
    }

    @discardableResult
    func send(_ text: String, recipient: String, command: String, timeout: TimeInterval = 15) async -> Bool {
        if Self.isUsableCommand(command) {
            if let result = await CommandRunner.run(command, [text], timeout: timeout), result.status == 0 {
                log.notice("Phone notice sent by the notification command")
                return true
            }
            log.error("Notification command failed — falling back to iMessage")
        }
        return await sendIMessage(text, to: recipient, timeout: timeout)
    }

    private func sendIMessage(_ text: String, to recipient: String, timeout: TimeInterval) async -> Bool {
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

    /// A plausible path (see `AwayNotice.isPlausibleCommandPath`) to a regular file this user owns
    /// and can execute, that neither the group nor others can write.
    private static func isUsableCommand(_ path: String) -> Bool {
        guard AwayNotice.isPlausibleCommandPath(path) else { return false }
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        let isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
        let writableByOthers = (info.st_mode & (S_IWGRP | S_IWOTH)) != 0
        return isRegularFile && info.st_uid == getuid() && !writableByOthers && access(path, X_OK) == 0
    }
}
