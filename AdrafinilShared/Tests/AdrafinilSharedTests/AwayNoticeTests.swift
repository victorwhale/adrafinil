import Foundation
import Testing
@testable import AdrafinilShared

/// A phone notice (iMessage to the user) when work behind a closed lid ends or is cut off, so the
/// user away from the Mac knows when to open it again.
@Suite("AwayNotice")
struct AwayNoticeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ["+33632939718", "+14155551234", "victor@example.com", "a.b-c+d@sub.example.eu"])
    func `valid recipients`(recipient: String) {
        #expect(AwayNotice.isValidRecipient(recipient))
    }

    @Test(arguments: ["", "0632939718", "+33 6 32", "+12", "victor@", "@example.com", "a b@example.com", "\"; do shell script \"x", "+336329397181234567", "-e--x@a.b", ".a@b.c"])
    func `invalid recipients are refused`(recipient: String) {
        #expect(!AwayNotice.isValidRecipient(recipient))
    }

    @Test
    func `notifies once the last agent is done behind a closed lid`() {
        #expect(AwayNotice.shouldNotifyWorkFinished(recipient: "+33632939718", lidClosedAlone: true, agentsLeft: 0, lastSent: nil, now: now))
    }

    @Test
    func `stays quiet with the lid open, agents still working, no recipient, or a notice just sent`() {
        #expect(!AwayNotice.shouldNotifyWorkFinished(recipient: "+33632939718", lidClosedAlone: false, agentsLeft: 0, lastSent: nil, now: now))
        #expect(!AwayNotice.shouldNotifyWorkFinished(recipient: "+33632939718", lidClosedAlone: true, agentsLeft: 2, lastSent: nil, now: now))
        #expect(!AwayNotice.shouldNotifyWorkFinished(recipient: "", lidClosedAlone: true, agentsLeft: 0, lastSent: nil, now: now))
        #expect(!AwayNotice.shouldNotifyWorkFinished(recipient: "+33632939718", lidClosedAlone: true, agentsLeft: 0, lastSent: now.addingTimeInterval(-120), now: now))
        #expect(AwayNotice.shouldNotifyWorkFinished(recipient: "+33632939718", lidClosedAlone: true, agentsLeft: 0, lastSent: now.addingTimeInterval(-601), now: now))
    }

    @Test(arguments: ["/Users/v/code/claude-comptes/bin/alerte-sms", "/usr/local/bin/notify"])
    func `plausible notification commands`(path: String) {
        #expect(AwayNotice.isPlausibleCommandPath(path))
    }

    @Test(arguments: ["", "alerte-sms", "~/bin/alerte-sms", "/Users/v/../../etc/x", "/tmp/a\nb", "./alerte-sms", "/a/./b"])
    func `relative, traversing or odd command paths are refused`(path: String) {
        #expect(!AwayNotice.isPlausibleCommandPath(path))
    }

    @Test
    func `a command alone is a channel, no recipient needed`() {
        #expect(AwayNotice.hasChannel(recipient: "", command: "/Users/v/bin/alerte-sms"))
        #expect(AwayNotice.hasChannel(recipient: "+33632939718", command: ""))
        #expect(!AwayNotice.hasChannel(recipient: "", command: ""))
        #expect(AwayNotice.shouldNotifyWorkFinished(recipient: "", command: "/Users/v/bin/alerte-sms", lidClosedAlone: true, agentsLeft: 0, lastSent: nil, now: now))
        #expect(!AwayNotice.shouldNotifyWorkFinished(recipient: "", command: "relative", lidClosedAlone: true, agentsLeft: 0, lastSent: nil, now: now))
    }

    @Test
    func `the texts say what happened and what comes next`() {
        #expect(AwayNotice.workFinishedText(graceMinutes: 5) == "Adrafinil : Claude a fini. Le Mac se met en veille dans 5 min.")
        #expect(AwayNotice.workFinishedText(graceMinutes: 0) == "Adrafinil : Claude a fini. Le Mac se met en veille.")
        #expect(AwayNotice.thermalCutoutText(celsius: 82.6) == "Adrafinil : coupure à 83 °C, trop chaud. Le Mac se met en veille.")
        #expect(AwayNotice.thermalCutoutText(celsius: nil) == "Adrafinil : coupure, trop chaud. Le Mac se met en veille.")
        #expect(AwayNotice.lowBatteryCutoutText(percent: 19) == "Adrafinil : batterie à 19 %. Le Mac se met en veille.")
        #expect(AwayNotice.confirmationText == "Adrafinil : les alertes du Mac arriveront ici.")
    }
}
