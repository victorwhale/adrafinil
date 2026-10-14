import Testing
@testable import AdrafinilShared

/// A safety cutout must actually sleep a lid-closed Mac — but only in the clamshell-sleep case,
/// and only once the block is confirmed cleared. With `sleepWhenWorkEnds`, finished work sleeps
/// it too: macOS never replays the lid-close sleep a hold carried the Mac past.
@Suite("CutoutSleepDecider")
struct CutoutSleepDeciderTests {
    private let d = CutoutSleepDecider()

    @Test
    func `a cutout with the lid closed and no external display sleeps`() {
        #expect(d.shouldSleep(cause: .safetyCutout, onlyDisplayIsClosedBuiltIn: true, blockCleared: true))
    }

    @Test
    func `an external display or an open lid keeps the Mac awake`() {
        #expect(!d.shouldSleep(cause: .safetyCutout, onlyDisplayIsClosedBuiltIn: false, blockCleared: true))
        #expect(!d.shouldSleep(cause: .workComplete, onlyDisplayIsClosedBuiltIn: false, blockCleared: true, sleepWhenWorkEnds: true))
    }

    @Test
    func `a block that failed to clear is not slept against`() {
        #expect(!d.shouldSleep(cause: .safetyCutout, onlyDisplayIsClosedBuiltIn: true, blockCleared: false))
        #expect(!d.shouldSleep(cause: .workComplete, onlyDisplayIsClosedBuiltIn: true, blockCleared: false, sleepWhenWorkEnds: true))
    }

    @Test(arguments: [ReleaseCause.workComplete, .holdExpired, .userAction])
    func `other release causes leave sleep to macOS by default`(cause: ReleaseCause) {
        #expect(!d.shouldSleep(cause: cause, onlyDisplayIsClosedBuiltIn: true, blockCleared: true))
    }

    @Test(arguments: [ReleaseCause.workComplete, .holdExpired])
    func `finished or expired work sleeps a closed lid when asked to`(cause: ReleaseCause) {
        #expect(d.shouldSleep(cause: cause, onlyDisplayIsClosedBuiltIn: true, blockCleared: true, sleepWhenWorkEnds: true))
    }

    @Test
    func `a release by the user never sleeps the Mac out from under them`() {
        #expect(!d.shouldSleep(cause: .userAction, onlyDisplayIsClosedBuiltIn: true, blockCleared: true, sleepWhenWorkEnds: true))
    }
}
