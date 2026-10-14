import Testing
@testable import AdrafinilShared

/// Low Power Mode while the lid is closed: read each power source's current mode from
/// `pmset -g custom`, switch only the ones not already in Low Power Mode, and remember their
/// original mode so it can be put back exactly.
@Suite("LowPowerPlan")
struct LowPowerPlanTests {
    private let modernOutput = """
    Battery Power:
     Sleep On Power Button 1
     powermode            1
     standby              1
     sleep                0
    AC Power:
     Sleep On Power Button 1
     powermode            0
     standby              1
     sleep                0
    """

    @Test
    func `reads the power mode of each source`() {
        #expect(LowPowerPlan.parse(pmsetCustom: modernOutput) == [.battery: 1, .ac: 0])
    }

    @Test
    func `reads the older lowpowermode key too`() {
        let older = """
        Battery Power:
         lowpowermode         0
        AC Power:
         lowpowermode         0
        """
        #expect(LowPowerPlan.parse(pmsetCustom: older) == [.battery: 0, .ac: 0])
    }

    @Test
    func `a desktop Mac without a battery section yields only AC`() {
        #expect(LowPowerPlan.parse(pmsetCustom: "AC Power:\n powermode 2\n") == [.ac: 2])
    }

    @Test
    func `garbage yields nothing`() {
        #expect(LowPowerPlan.parse(pmsetCustom: "pmset: error").isEmpty)
    }

    @Test
    func `only sources outside Low Power Mode are switched, keeping their original mode`() {
        #expect(LowPowerPlan.originalsToRestore(current: [.battery: 1, .ac: 0]) == [.ac: 0])
        #expect(LowPowerPlan.originalsToRestore(current: [.battery: 2, .ac: 0]) == [.battery: 2, .ac: 0])
        #expect(LowPowerPlan.originalsToRestore(current: [.battery: 1, .ac: 1]).isEmpty)
    }

    @Test
    func `the pmset flag of each source`() {
        #expect(PowerSource.battery.pmsetFlag == "-b")
        #expect(PowerSource.ac.pmsetFlag == "-c")
    }

    @Test(arguments: [0, 1, 2])
    func `valid power modes`(mode: Int) {
        #expect(LowPowerPlan.isValidMode(mode))
    }

    @Test(arguments: [-1, 3, 99])
    func `invalid power modes are refused`(mode: Int) {
        #expect(!LowPowerPlan.isValidMode(mode))
    }
}
