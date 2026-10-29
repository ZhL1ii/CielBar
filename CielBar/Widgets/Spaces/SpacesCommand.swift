import Darwin
import Foundation

/// Runs a short window-manager command off the main thread with a bounded lifetime.
enum SpacesCommand {
    enum Failure: LocalizedError {
        case launch(String)
        case timedOut
        case exited(Int32)
        case terminated(Int32)

        var errorDescription: String? {
            switch self {
            case .launch(let message): return "Command launch failed: \(message)"
            case .timedOut: return "Command timed out after 2 seconds"
            case .exited(let status): return "Command exited with status \(status)"
            case .terminated(let signal): return "Command terminated by signal \(signal)"
            }
        }
    }

    static func run(executablePath: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        defer { try? output.fileHandleForReading.close() }

        do {
            try process.run()
        } catch {
            throw Failure.launch(error.localizedDescription)
        }

        let timeoutReached = DispatchSemaphore(value: 0)
        let timeout = DispatchWorkItem {
            if process.isRunning {
                timeoutReached.signal()
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 2, execute: timeout)
        defer { timeout.cancel() }

        // Drain stdout while the command runs, including output larger than a pipe buffer.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if timeoutReached.wait(timeout: .now()) == .success { throw Failure.timedOut }
        guard process.terminationReason == .exit else {
            throw Failure.terminated(process.terminationStatus)
        }
        guard process.terminationStatus == 0 else {
            throw Failure.exited(process.terminationStatus)
        }
        return data
    }
}
