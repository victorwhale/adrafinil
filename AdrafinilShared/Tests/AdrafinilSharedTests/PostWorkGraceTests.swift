import Foundation
import Testing
@testable import AdrafinilShared

/// The post-work grace keeps the Mac awake a few minutes after the last agent finishes, so a
/// follow-up prompt (or a reply from a phone) lands on a running Mac instead of a sleeping one.
@Suite("PostWorkGrace")
struct PostWorkGraceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func agent(_ key: String) -> Assertion {
        Assertion(key: key, tool: "claude-code", pid: 42, processName: "claude")
    }

    @Test
    func `the grace key is a reserved hold key, so no CLI caller can collide with it`() {
        #expect(ManualHold.isHoldKey(PostWorkGrace.key))
        #expect(CLIRequestValidator.reservedKeyPrefixes.contains { PostWorkGrace.key.hasPrefix($0) })
    }

    @Test
    func `the grace assertion is an idle-exempt manual hold that expires after the grace`() throws {
        let grace = try #require(PostWorkGrace.assertion(minutes: 5, now: now))
        #expect(grace.key == PostWorkGrace.key)
        #expect(grace.origin == .manual)
        #expect(grace.pid == -1)
        #expect(grace.expiresAt == now.addingTimeInterval(300))
        #expect(!grace.holdsDisplay)
    }

    @Test(arguments: [0, -3])
    func `a zero grace places nothing`(minutes: Int) {
        #expect(PostWorkGrace.assertion(minutes: minutes, now: now) == nil)
    }

    @Test
    func `releasing a held agent arms the grace`() {
        #expect(PostWorkGrace.shouldArm(releasing: ["claude-code:a"], held: [agent("claude-code:a")], minutes: 5))
    }

    @Test
    func `a release that matches nothing, or only the grace itself, does not re-arm it`() throws {
        #expect(!PostWorkGrace.shouldArm(releasing: ["claude-code:gone"], held: [agent("claude-code:a")], minutes: 5))
        let grace = try #require(PostWorkGrace.assertion(minutes: 5, now: now))
        #expect(!PostWorkGrace.shouldArm(releasing: [PostWorkGrace.key], held: [grace], minutes: 5))
    }

    @Test
    func `no grace when it is turned off`() {
        #expect(!PostWorkGrace.shouldArm(releasing: ["claude-code:a"], held: [agent("claude-code:a")], minutes: 0))
    }

    @Test
    func `the grace running out reads as finished work, not an expired hold`() {
        let releases = [IdleReleaseEvaluator.Release(key: PostWorkGrace.key, reason: .ttlExpired)]
        #expect(PostWorkGrace.cause(forIdleReleases: releases) == .workComplete)
    }

    @Test
    func `other expiries keep their usual cause`() {
        let expired = [IdleReleaseEvaluator.Release(key: "hold:abc", reason: .ttlExpired)]
        #expect(PostWorkGrace.cause(forIdleReleases: expired) == .holdExpired)
        let mixed = expired + [IdleReleaseEvaluator.Release(key: "claude-code:a", reason: .cpuIdle)]
        #expect(PostWorkGrace.cause(forIdleReleases: mixed) == .workComplete)
    }
}
