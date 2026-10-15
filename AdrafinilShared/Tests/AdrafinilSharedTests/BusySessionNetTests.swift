import Foundation
import Testing
@testable import AdrafinilShared

/// The busy-session net: a Claude Code session its own status file says is working, but that no
/// hook holds (a missed hook, an app or daemon restart, a pause and resume), is held under the
/// very key its hooks use — so its end hook releases it as usual.
@Suite("BusySessionNet")
struct BusySessionNetTests {
    private func status(_ pid: pid_t, _ session: String, _ activity: ClaudeSessionStatus.Activity) -> ClaudeSessionStatus {
        ClaudeSessionStatus(pid: pid, sessionID: session, activity: activity)
    }

    @Test
    func `a busy live session no hook holds is picked up`() {
        let missing = BusySessionNet.missing(
            statuses: [status(10, "s-busy", .busy)],
            heldKeys: [],
            suppressedKeys: [],
            isClaudeProcess: { _ in true },
        )
        #expect(missing.map(\.sessionID) == ["s-busy"])
    }

    @Test
    func `idle or waiting sessions, dead processes and held sessions are left alone`() {
        let statuses = [
            status(1, "idle", .idle),
            status(2, "waiting", .waiting),
            status(3, "dead", .busy),
            status(4, "held", .busy),
        ]
        let missing = BusySessionNet.missing(
            statuses: statuses,
            heldKeys: [BusySessionNet.key(sessionID: "held")],
            suppressedKeys: [],
            isClaudeProcess: { $0 != 3 },
        )
        #expect(missing.isEmpty)
    }

    @Test
    func `the key is the one the Claude Code hooks use`() {
        #expect(BusySessionNet.key(sessionID: "e1fee3c6") == "claude-code:e1fee3c6")
        #expect(BusySessionNet.key(sessionID: "e1fee3c6") == ManualHold.sessionKey(tool: AgentKind.claudeCode.rawValue, sessionID: "e1fee3c6"))
    }

    @Test
    func `the hold behaves like a hook hold, idle release and waiting policy included`() {
        let hold = BusySessionNet.assertion(for: status(42, "s", .busy))
        #expect(hold.key == "claude-code:s")
        #expect(hold.tool == AgentKind.claudeCode.rawValue)
        #expect(hold.pid == 42)
        #expect(hold.origin == .hook)
        #expect(hold.expiresAt == nil)
    }

    @Test
    func `one session listed twice is picked up once`() {
        let missing = BusySessionNet.missing(
            statuses: [status(10, "s", .busy), status(10, "s", .busy)],
            heldKeys: [],
            suppressedKeys: [],
            isClaudeProcess: { _ in true },
        )
        #expect(missing.count == 1)
    }

    @Test
    func `a session released while still marked busy is not taken back`() {
        let missing = BusySessionNet.missing(
            statuses: [status(10, "s", .busy)],
            heldKeys: [],
            suppressedKeys: [BusySessionNet.key(sessionID: "s")],
            isClaudeProcess: { _ in true },
        )
        #expect(missing.isEmpty)
    }

    @Test
    func `a release is forgotten once the session leaves busy, so its next turn counts again`() {
        let suppressed: Set = [BusySessionNet.key(sessionID: "still"), BusySessionNet.key(sessionID: "done"), BusySessionNet.key(sessionID: "gone")]
        let kept = BusySessionNet.stillSuppressed(suppressed, statuses: [status(1, "still", .busy), status(2, "done", .idle)])
        #expect(kept == [BusySessionNet.key(sessionID: "still")])
    }

    @Test
    func `a session id that could reach the reserved key space is never used`() {
        let missing = BusySessionNet.missing(
            statuses: [status(10, "hold:post-work-grace", .busy), status(11, "claude-code:x", .busy), status(12, "", .busy)],
            heldKeys: [],
            suppressedKeys: [],
            isClaudeProcess: { _ in true },
        )
        #expect(missing.isEmpty)
        #expect(BusySessionNet.isPlausibleSessionID("e1fee3c6-c316-4564-8519-b6a1fcbe511e"))
    }

    @Test
    func `status files are read from every directory, the auth key files never`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a", isDirectory: true)
        let b = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try Data(#"{"pid": 11, "sessionId": "one", "status": "busy"}"#.utf8).write(to: a.appendingPathComponent("11.json"))
        try Data(#"{"pid": 22, "sessionId": "two", "status": "idle"}"#.utf8).write(to: b.appendingPathComponent("22.json"))
        try Data("secret".utf8).write(to: b.appendingPathComponent("22.abc.key"))
        let read = ClaudeSessionStatus.readAll(in: [a, b, root.appendingPathComponent("missing")])
        #expect(Set(read.map(\.sessionID)) == ["one", "two"])
    }
}
