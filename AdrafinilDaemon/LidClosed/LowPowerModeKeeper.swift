import AdrafinilShared
import Foundation
import OSLog

/// Holds the Mac in Low Power Mode while an agent works behind a closed lid, then puts each
/// power source back in its own mode (see `LowPowerPlan`).
///
/// The originals are persisted before the daemon relies on them, so a crash, a SIGTERM that
/// beats the restore, or a reboot mid-hold still restores them: the next `update` after launch
/// finds them on disk and puts them back. Updates are serialized, so an engage still in flight
/// can't land after the restore that should have followed it.
@MainActor
final class LowPowerModeKeeper {
    private let log = Logger(subsystem: AdrafinilConstants.daemonBundleID, category: "LowPowerMode")
    private let helperClient: HelperClient
    private let storeURL: URL

    /// Sources this keeper switched to Low Power Mode, mapped to the mode to restore.
    private var originals: [PowerSource: Int]
    private var engaged = false
    private var pending: Task<Void, Never>?

    /// Whether Low Power Mode is currently being held for a closed-lid agent.
    var isEngaged: Bool {
        engaged
    }

    init(
        helperClient: HelperClient,
        storeURL: URL = AdrafinilConstants.appSupportURL.appendingPathComponent("low-power-restore.json"),
    ) {
        self.helperClient = helperClient
        self.storeURL = storeURL
        let stored = (try? Data(contentsOf: storeURL)).flatMap { try? JSONDecoder().decode([PowerSource: Int].self, from: $0) }
        originals = stored ?? [:]
    }

    func update(wanted: Bool) async {
        let previous = pending
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.apply(wanted: wanted)
        }
        pending = task
        await task.value
    }

    private func apply(wanted: Bool) async {
        if wanted, !engaged {
            await engage()
        } else if !wanted, engaged || !originals.isEmpty {
            await restore()
        }
    }

    private func engage() async {
        guard let result = await CommandRunner.run("/usr/bin/pmset", ["-g", "custom"], timeout: 5), result.status == 0 else {
            log.error("Could not read the power modes (pmset -g custom) — Low Power Mode left as is")
            return
        }
        let current = LowPowerPlan.parse(pmsetCustom: result.output)
        // An original already on record (from a run that crashed mid-hold) is the true one: the
        // source now reads Low Power because we put it there. Each original is on disk *before*
        // the switch, so no crash can leave a source switched with nothing to restore it.
        var allApplied = true
        for (source, original) in LowPowerPlan.originalsToRestore(current: current) where originals[source] == nil {
            originals[source] = original
            save()
            if await !helperClient.setPowerMode(LowPowerPlan.lowPowerMode, source: source) {
                originals[source] = nil
                save()
                allApplied = false
            }
        }
        // A failed switch leaves `engaged` false, so the next update (the 60s reconcile) retries.
        engaged = allApplied
        log.notice("Low Power Mode on for the closed lid (restoring later: \(self.describe(self.originals), privacy: .public))")
    }

    private func restore() async {
        for (source, mode) in originals {
            if await helperClient.setPowerMode(mode, source: source) {
                originals[source] = nil
            }
        }
        save()
        engaged = false
        if originals.isEmpty {
            log.notice("Power modes restored")
        } else {
            log.error("Some power modes could not be restored yet: \(self.describe(self.originals), privacy: .public) — retrying on the next update")
        }
    }

    private func save() {
        if originals.isEmpty {
            try? FileManager.default.removeItem(at: storeURL)
        } else if let data = try? JSONEncoder().encode(originals) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private func describe(_ modes: [PowerSource: Int]) -> String {
        modes.isEmpty ? "nothing" : modes.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", ")
    }
}
