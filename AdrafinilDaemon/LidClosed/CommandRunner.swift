import Foundation

/// Runs a short-lived system tool (`pmset -g`, `ipconfig`, `networksetup`) off the main actor,
/// with a deadline, and hands back its exit status and combined output. These tools print a
/// few lines at most, so the output is read once the process exits.
enum CommandRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    /// Nil if the tool could not be launched or outlived `timeout` (it is then terminated).
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> Result? {
        await withCheckedContinuation { (cont: CheckedContinuation<Result?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runBlocking(path, arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Result? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        do {
            try task.run()
        } catch {
            return nil
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            task.terminate()
            _ = exited.wait(timeout: .now() + 2)
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Result(status: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
