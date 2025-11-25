//
//  EasyPipe.swift
//  GitX
//
//  Swift conversion of PBEasyPipe
//  Original by Pieter de Bie on 16-06-08
//

import Foundation

public enum EasyPipe {

    public struct CommandResult {
        public let output: String
        public let exitCode: Int32
    }

    public static func createTask(
        command: String,
        arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = arguments

        // Prepare environment, removing debug-related keys
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "MallocStackLogging")
        env.removeValue(forKey: "MallocStackLoggingNoCompact")
        env.removeValue(forKey: "NSZombieEnabled")

        if let additionalEnv = environment {
            env.merge(additionalEnv) { _, new in new }
        }
        task.environment = env

        if let dir = directory {
            task.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "Show Debug Messages") {
            print("Starting command `\(command) \(arguments.joined(separator: " "))` in dir \(directory ?? "nil")")
        }
        #endif

        return task
    }

    public static func fileHandle(
        for command: String,
        arguments: [String],
        directory: String? = nil
    ) throws -> FileHandle {
        let task = createTask(command: command, arguments: arguments, directory: directory)
        guard let pipe = task.standardOutput as? Pipe else {
            throw NSError(domain: "EasyPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pipe"])
        }

        try task.run()
        return pipe.fileHandleForReading
    }

    @discardableResult
    public static func output(
        for command: String,
        arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        input: String? = nil
    ) throws -> CommandResult {
        let task = createTask(
            command: command,
            arguments: arguments,
            directory: directory,
            environment: environment
        )

        guard let outputPipe = task.standardOutput as? Pipe else {
            throw NSError(domain: "EasyPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output pipe"])
        }

        if let inputString = input {
            let inputPipe = Pipe()
            task.standardInput = inputPipe

            if let data = inputString.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
                inputPipe.fileHandleForWriting.closeFile()
            }
        }

        try task.run()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        var outputString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""

        // Strip trailing newline
        if outputString.hasSuffix("\n") {
            outputString.removeLast()
        }

        task.waitUntilExit()

        return CommandResult(output: outputString, exitCode: task.terminationStatus)
    }

    public static func outputAsync(
        for command: String,
        arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        input: String? = nil
    ) async throws -> CommandResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let result = try output(
                        for: command,
                        arguments: arguments,
                        directory: directory,
                        environment: environment,
                        input: input
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
