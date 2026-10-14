import AdrafinilShared
import Foundation
import os
import OSLog

/// Runs `/usr/bin/pmset` with a deadline. Throws if it exits non-zero or wedges.
enum PMSet {
    private static let log = Logger(subsystem: AdrafinilConstants.helperBundleID, category: "PMSet")

    /// How long `pmset` may run before it counts as wedged. It normally exits in well under a
    /// second; the bound exists because the clamshell call runs under the helper's policy lock —
    /// an unbounded wait would deadlock every later XPC call, and the daemon's whole
    /// blocking-drive loop behind it.
    private static let timeout: TimeInterval = 10

    static func run(_ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = arguments
        let command = "pmset " + arguments.joined(separator: " ")

        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()

        // Drain stderr while pmset runs: reading only after exit deadlocks if it ever fills the
        // pipe, and the helper would then hold its policy lock forever.
        let errBuffer = OSAllocatedUnfairLock(initialState: Data())
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { errBuffer.withLock { $0.append(chunk) } }
        }
        defer { errPipe.fileHandleForReading.readabilityHandler = nil }

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        try task.run()

        guard exited.wait(timeout: .now() + timeout) == .success else {
            log.error("\(command, privacy: .public) did not exit within \(timeout, privacy: .public)s — killing it")
            task.terminate()
            _ = exited.wait(timeout: .now() + 2)
            throw NSError(
                domain: "Adrafinil.Helper.PMSet",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "pmset timed out"],
            )
        }
        log.notice("\(command, privacy: .public) exited \(task.terminationStatus, privacy: .public)")

        guard task.terminationStatus == 0 else {
            let err = errBuffer.withLock { $0 }
            let msg = String(data: err, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } ?? "pmset exited \(task.terminationStatus)"
            throw NSError(
                domain: "Adrafinil.Helper.PMSet",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg],
            )
        }
    }
}
