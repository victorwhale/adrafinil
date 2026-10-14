import Foundation

/// A power source as `pmset` addresses it.
public enum PowerSource: String, Codable, Sendable, CaseIterable {
    case battery
    case ac

    /// The `pmset` flag selecting this source's settings profile.
    public var pmsetFlag: String {
        switch self {
        case .battery: "-b"
        case .ac: "-c"
        }
    }
}

/// Low Power Mode while an agent works behind a closed lid. Pure.
///
/// A Mac kept awake in a bag gains nothing from full performance: Low Power Mode cuts heat and
/// drain, and the agents' work is network- and model-bound anyway. The daemon reads each source's
/// mode (`pmset -g custom`, no privileges), switches only the sources not already in Low Power
/// Mode, and remembers their original mode so it can be restored exactly — including High Power
/// Mode, which a blanket "low power off" would lose.
public enum LowPowerPlan {
    /// `powermode` values: 0 automatic, 1 Low Power, 2 High Power.
    public static let lowPowerMode = 1

    public static func isValidMode(_ mode: Int) -> Bool {
        (0 ... 2).contains(mode)
    }

    /// Each source's current mode, from `pmset -g custom`. Reads `powermode` (current macOS) or
    /// the older boolean `lowpowermode`; sources without either line are left out.
    public static func parse(pmsetCustom output: String) -> [PowerSource: Int] {
        var modes: [PowerSource: Int] = [:]
        var current: PowerSource?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Battery Power:") {
                current = .battery
            } else if line.hasPrefix("AC Power:") {
                current = .ac
            } else if let source = current {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2, fields[0] == "powermode" || fields[0] == "lowpowermode",
                      let value = Int(fields[1]), isValidMode(value) else { continue }
                modes[source] = value
            }
        }
        return modes
    }

    /// The sources to switch to Low Power Mode, mapped to the mode to restore afterwards.
    public static func originalsToRestore(current: [PowerSource: Int]) -> [PowerSource: Int] {
        current.filter { $0.value != lowPowerMode }
    }
}
