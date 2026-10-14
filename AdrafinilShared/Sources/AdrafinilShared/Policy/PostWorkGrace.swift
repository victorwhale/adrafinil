import Foundation

/// A short keep-awake window after an agent finishes. Pure.
///
/// The end hook releases the moment a turn ends, but the user often follows up within minutes —
/// at the keyboard or from a phone — and a Mac that slept in between drops that follow-up. The
/// daemon places this one well-known hold *before* releasing the agent, so the registry never
/// empties mid-handoff: the Mac sleeps only once the grace runs out with nothing else held. Each
/// further release re-arms it, so it always measures from the last agent to finish.
///
/// It is an ordinary `.manual` hold: exempt from the CPU-idle rule, bounded by its TTL, shown in
/// the menu with a countdown, and releasable there like any other hold.
public enum PostWorkGrace {
    /// Under the reserved `hold:` prefix, so no CLI caller can mint or release it by accident.
    public static let key = ManualHold.keyPrefix + "post-work-grace"
    public static let tool = "grace"
    public static let reason = "Grace period after the agents finished"

    /// The grace hold to place now, or nil when the grace is off.
    public static func assertion(minutes: Int, now: Date = Date()) -> Assertion? {
        guard minutes > 0 else { return nil }
        return Assertion(
            key: key,
            tool: tool,
            reason: reason,
            pid: -1,
            processName: tool,
            acquiredAt: now,
            ttl: TimeInterval(minutes * 60),
            origin: .manual,
        )
    }

    /// Whether releasing `keys` should (re-)arm the grace: something real is being released —
    /// not an unknown key, and not the grace itself running out.
    public static func shouldArm(releasing keys: [String], held: [Assertion], minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        let heldKeys = Set(held.map(\.key))
        return keys.contains { $0 != key && heldKeys.contains($0) }
    }

    /// The cause of an idle-sweep batch, treating the grace running out as finished work: the
    /// agents were done when it was armed, so the "work may not be done" cue would be wrong.
    public static func cause(forIdleReleases releases: [IdleReleaseEvaluator.Release]) -> ReleaseCause {
        if !releases.isEmpty, releases.allSatisfy({ $0.key == key }) {
            return .workComplete
        }
        return ReleaseCause(idleReleaseReasons: releases.map(\.reason))
    }
}
