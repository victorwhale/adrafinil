import AdrafinilShared
import Darwin
import Foundation
import OSLog

extension Daemon {
    /// One pass of the busy-session net (see `BusySessionNet`): every Claude Code session its status
    /// file says is working, alive, and held by nothing, is held again under its hook key. Paused
    /// means hold nothing; `handleAcquire` also refuses while a safety cutout is latched.
    func busySessionSweep() async {
        guard settings.holdBusyClaudeSessions, !isPaused else { return }
        let held = await Set(registry.snapshot().map(\.key))
        let statuses = ClaudeSessionStatus.readAll(in: ClaudeSessionStatus.sessionDirectories())
        busyNetSuppressed = BusySessionNet.stillSuppressed(busyNetSuppressed, statuses: statuses)
        let missing = BusySessionNet.missing(
            statuses: statuses,
            heldKeys: held,
            suppressedKeys: busyNetSuppressed,
            isClaudeProcess: Self.isOwnClaudeProcess,
        )
        for status in missing where await handleAcquire(BusySessionNet.assertion(for: status)) == .accepted {
            log.notice("Busy Claude session pid \(status.pid, privacy: .public) had no hold — held under its hook key")
        }
    }

    /// Remembers releases for the busy-session net, so a session let go while still marked busy
    /// isn't taken straight back (see `BusySessionNet`). Pauses and cutouts don't come through here.
    func noteReleasedForBusyNet(_ keys: [String]) {
        guard settings.holdBusyClaudeSessions else { return }
        busyNetSuppressed.formUnion(keys)
    }

    /// A live process of ours (EPERM — another user's — never qualifies) that is `claude`: a stale
    /// status file whose pid now names something else is ignored.
    private static func isOwnClaudeProcess(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0, let path = ProcessResolver.path(of: pid) else { return false }
        return AgentKind.forRunningProcess(name: (path as NSString).lastPathComponent, path: path) == .claudeCode
    }
}
