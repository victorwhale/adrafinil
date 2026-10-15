import Foundation

/// A net under the Claude Code hooks. Pure.
///
/// The hooks acquire at a few precise moments — a prompt submitted, a sub-agent started, a
/// `/clear` — so a session already mid-turn when its hold was lost (a missed hook, the app or the
/// daemon restarted, a pause and resume) stays unheld until its next prompt, and a closed lid
/// would put it to sleep mid-work. Claude Code's own status file says which sessions are working
/// (`busy`, see `ClaudeSessionStatus`); a busy, live session that nothing holds is held again
/// under the very key its hooks use, so its end hook releases it as usual, and the CPU-idle and
/// waiting-on-user policies apply as to any hook hold.
///
/// Busy is Claude Code's own word for "a turn is in flight", whatever the CPU does: a session
/// waiting on the model can sit near 2% CPU, close to an idle prompt, so CPU alone can't tell.
///
/// A session released while its file still says busy (its end hook ran a beat before the status
/// flipped, the user released it from the menu, the idle sweep let it go) is not taken back: the
/// daemon remembers the release until the session leaves busy, so its next turn counts again. A
/// pause is not remembered — resuming is precisely when sessions mid-turn need holding again.
public enum BusySessionNet {
    public static func key(sessionID: String) -> String {
        ManualHold.sessionKey(tool: AgentKind.claudeCode.rawValue, sessionID: sessionID)
    }

    /// A Claude Code session id (a UUID): letters, digits, `-` and `_` only — never a `:` that could
    /// reach the reserved `hold:` space or another tool's keys.
    public static func isPlausibleSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }

    /// The busy sessions of live `claude` processes that nothing holds and that weren't released
    /// during this busy spell, each once.
    public static func missing(
        statuses: [ClaudeSessionStatus],
        heldKeys: Set<String>,
        suppressedKeys: Set<String>,
        isClaudeProcess: (pid_t) -> Bool,
    ) -> [ClaudeSessionStatus] {
        var seen = Set<String>()
        return statuses.filter { status in
            guard status.activity == .busy, isPlausibleSessionID(status.sessionID) else { return false }
            let key = key(sessionID: status.sessionID)
            guard !heldKeys.contains(key), !suppressedKeys.contains(key), isClaudeProcess(status.pid) else { return false }
            return seen.insert(key).inserted
        }
    }

    /// The remembered releases that still apply: those whose session still reads busy.
    public static func stillSuppressed(_ suppressed: Set<String>, statuses: [ClaudeSessionStatus]) -> Set<String> {
        let busy = Set(statuses.filter { $0.activity == .busy }.map { key(sessionID: $0.sessionID) })
        return suppressed.intersection(busy)
    }

    /// The hold for a missed busy session: a hook hold in all but its reason.
    public static func assertion(for status: ClaudeSessionStatus) -> Assertion {
        Assertion(
            key: key(sessionID: status.sessionID),
            tool: AgentKind.claudeCode.rawValue,
            reason: "busy session without a hook hold",
            pid: status.pid,
            processName: "claude",
            origin: .hook,
        )
    }
}
