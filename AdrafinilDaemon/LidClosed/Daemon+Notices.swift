import AdrafinilShared
import Foundation

extension Daemon {
    /// Texts the user "Claude is done" once the last agent finishes behind a closed lid — called
    /// after each agent release (end hook, process exit, CPU-idle). The post-work grace and any
    /// manual hold don't count as agents still working.
    func noticeIfWorkFinished() async {
        let agentsLeft = await registry.snapshot().count { $0.key != PostWorkGrace.key }
        await notifier.workFinished(
            recipient: settings.notifyRecipient,
            command: settings.notifyCommand,
            lidClosedAlone: DisplayHold.onlyDisplayIsClosedBuiltIn(lidClosed: lidMonitor.isLidClosed),
            agentsLeft: agentsLeft,
            graceMinutes: settings.postWorkGraceMinutes,
        )
    }
}
