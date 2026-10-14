import AdrafinilShared
import Foundation
import os
import OSLog

/// Runs `/usr/bin/pmset` (see `HelperTool`).
enum PMSet {
    static func run(_ arguments: [String]) throws {
        _ = try HelperTool.run("/usr/bin/pmset", arguments)
    }
}

/// Runs a system tool at a fixed absolute path with a deadline, arguments as an array (never a
/// shell), and returns its standard output. Throws if it exits non-zero or wedges.
enum HelperTool {
    private static let log = Logger(subsystem: AdrafinilConstants.helperBundleID, category: "HelperTool")

    /// How long a tool may run before it counts as wedged. `pmset` and `networksetup` normally exit
    /// in well under a second; the bound exists because the clamshell call runs under the helper's
    /// policy lock — an unbounded wait would deadlock every later XPC call.
    private static let timeout: TimeInterval = 10

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let command = (path as NSString).lastPathComponent + " " + arguments.joined(separator: " ")

        let errPipe = Pipe()
        let outPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = outPipe
        let outBuffer = OSAllocatedUnfairLock(initialState: Data())
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { outBuffer.withLock { $0.append(chunk) } }
        }
        defer { outPipe.fileHandleForReading.readabilityHandler = nil }

        // Drain both pipes while the tool runs: reading only after exit deadlocks if one ever
        // fills, and the helper would then hold its policy lock forever.
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
                domain: "Adrafinil.Helper.Tool",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(command) timed out"],
            )
        }
        log.notice("\(command, privacy: .public) exited \(task.terminationStatus, privacy: .public)")

        guard task.terminationStatus == 0 else {
            let err = errBuffer.withLock { $0 }
            let msg = String(data: err, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } ?? "\(command) exited \(task.terminationStatus)"
            throw NSError(
                domain: "Adrafinil.Helper.Tool",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg],
            )
        }
        // Collect whatever the handler hadn't picked up yet when the tool exited.
        outPipe.fileHandleForReading.readabilityHandler = nil
        let rest = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: outBuffer.withLock { $0 } + rest, as: UTF8.self)
    }
}
