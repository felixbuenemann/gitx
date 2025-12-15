//
//  gitx_cli.swift
//  GitX
//
//  Command-line interface for GitX
//  Swift conversion of gitx.m
//

import Foundation
import AppKit

// MARK: - Usage and Version

func usage(_ programName: String) -> Never {
    print("""
        Usage: \(programName) (--help|--version|--git-path)
           or: \(programName) (--commit)
           or: \(programName) (--all|--local|--branch) [branch/tag]
           or: \(programName) <revlist options>
           or: \(programName) (--diff)
           or: \(programName) (--init)
           or: \(programName) (--clone <repository> [destination])

            -h, --help             print this help
            -v, --version          prints version info for both GitX and git
            --git-path             prints the path to the directory containing git

        Repository path
            By default gitx opens the repository in the current directory.
            Use --git-dir= to send commands to a repository somewhere else.

            --git-dir=<path> [gitx commands]
                                   send the gitx commands to the repository located at <path>

        Commit/Stage view
            -c, --commit           start GitX in commit/stage mode

        Branch filter options
            --all [branch]         view history for all branches
            --local [branch]       view history for local branches only
            --branch [branch]      view history for the selected branch only

        RevList options
            See 'man git-log' and 'man git-rev-list' for options you can pass to gitx

        Diff options
            -d, --diff [<common diff options>] <commit>{0,2} [--] [<path>...]
                                    shows the diff in a window in GitX
            git diff [options] | gitx
                                    pipe diff output to a GitX window

        Creating repositories
            --init                  creates (or reinitializes) a git repository
            --clone <repository URL> [destination path]
                                    clones the repository
        """)
    exit(1)
}

func versionInfo() -> Never {
    let bundle = Bundle.main
    let version = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    print("GitX version \(version)")

    if let gitPath = findGitPath() {
        let gitVersion = runGit(["--version"]) ?? "unknown"
        print("Using git found at \(gitPath), version \(gitVersion.trimmingCharacters(in: .whitespacesAndNewlines))")
    } else {
        print("GitX cannot find a git binary")
    }
    exit(0)
}

func gitPath() -> Never {
    guard let path = findGitPath() else {
        exit(101)
    }
    print((path as NSString).deletingLastPathComponent)
    exit(0)
}

// MARK: - Git Binary

func findGitPath() -> String? {
    let paths = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git",
        "/opt/local/bin/git"
    ]

    for path in paths {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }

    // Try which
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = ["git"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
    } catch {}

    return nil
}

func runGit(_ arguments: [String], in directory: String? = nil) -> String? {
    guard let gitPath = findGitPath() else { return nil }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: gitPath)
    task.arguments = arguments
    if let dir = directory {
        task.currentDirectoryURL = URL(fileURLWithPath: dir)
    }

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

// MARK: - Repository Finding

func findGitRepository(from url: URL) -> URL? {
    var current = url
    let fileManager = FileManager.default

    while current.path != "/" {
        let gitDir = current.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
            return current
        }
        current = current.deletingLastPathComponent()
    }
    return nil
}

func workingDirectoryURL(_ arguments: inout [String]) -> URL? {
    let gitDirPrefix = "--git-dir="

    // Check for --git-dir= option
    if let first = arguments.first, first.hasPrefix(gitDirPrefix) {
        let path = String(first.dropFirst(gitDirPrefix.count))
        arguments.removeFirst()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            print("Fatal: --git-dir path does not exist or is not a directory.")
            exit(2)
        }
        return URL(fileURLWithPath: path)
    }

    // Check if first argument is a path (not an option starting with -)
    if let first = arguments.first, !first.hasPrefix("-") {
        let expandedPath = NSString(string: first).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) {
            arguments.removeFirst()
            let url = URL(fileURLWithPath: expandedPath)
            if let repoURL = findGitRepository(from: url) {
                return repoURL
            }
            // Not a git repo, but path exists - return it anyway
            if isDir.boolValue {
                return url
            }
        }
    }

    // Fall back to current working directory
    guard let pwd = ProcessInfo.processInfo.environment["PWD"] else {
        return nil
    }

    return findGitRepository(from: URL(fileURLWithPath: pwd))
}

// MARK: - Handlers

func handleSTDINDiff() {
    let handle = FileHandle.standardInput
    let data = handle.readDataToEndOfFile()
    guard let diff = String(data: data, encoding: .utf8), !diff.isEmpty else {
        return
    }

    // Open GitX with diff via AppleScript
    let script = """
        tell application "GitX"
            activate
            show diff "\(diff.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
    exit(0)
}

func handleDiff(repositoryURL: URL, arguments: [String]) -> Never {
    let args = ["diff", "--no-ext-diff"] + arguments

    guard let output = runGit(args, in: repositoryURL.path) else {
        print("Invalid diff command")
        exit(3)
    }

    // Open GitX with diff
    let escapedDiff = output.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    let script = """
        tell application "GitX"
            activate
            show diff "\(escapedDiff)"
        end tell
        """

    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
    exit(0)
}

// Find the GitX.app bundle that contains this CLI tool
func findGitXApp() -> URL? {
    // This CLI tool is at GitX.app/Contents/Resources/gitx
    // So we need to go up 3 levels to get to GitX.app
    let executablePath = CommandLine.arguments[0]
    let executableURL = URL(fileURLWithPath: executablePath).standardized

    // Walk up to find the .app bundle
    var current = executableURL.deletingLastPathComponent()
    for _ in 0..<5 {
        if current.pathExtension == "app" {
            return current
        }
        current = current.deletingLastPathComponent()
    }

    // Fallback to /Applications/GitX.app
    let fallback = URL(fileURLWithPath: "/Applications/GitX.app")
    if FileManager.default.fileExists(atPath: fallback.path) {
        return fallback
    }

    return nil
}

func handleOpenRepository(repositoryURL: URL, arguments: [String]) {
    guard let gitxApp = findGitXApp() else {
        print("Could not find GitX.app")
        exit(2)
    }

    // Open the repository in GitX
    NSWorkspace.shared.open(
        [repositoryURL],
        withApplicationAt: gitxApp,
        configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
        if let error = error {
            print("Unable to open GitX.app: \(error.localizedDescription)")
            exit(2)
        }
    }

    // Give time for the app to open
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
}

func handleInit(repositoryURL: URL) -> Never {
    _ = runGit(["init"], in: repositoryURL.path)
    handleOpenRepository(repositoryURL: repositoryURL, arguments: [])
    exit(0)
}

func handleClone(repositoryURL: URL, arguments: [String]) -> Never {
    guard !arguments.isEmpty else {
        print("Error: --clone needs the URL of the repository to clone.")
        exit(2)
    }

    let repoToClone = arguments[0]
    var destination = repositoryURL

    if arguments.count > 1 {
        destination = URL(fileURLWithPath: arguments[1])
    }

    // Clone using git
    _ = runGit(["clone", repoToClone, destination.path])

    // Open cloned repo
    handleOpenRepository(repositoryURL: destination, arguments: [])
    exit(0)
}

// MARK: - Main

// MARK: - Main Entry Point

var arguments = Array(CommandLine.arguments.dropFirst())

// Handle help/version/git-path
if let first = arguments.first {
    switch first {
    case "--help", "-h":
        usage(CommandLine.arguments[0])
    case "--version", "-v":
        versionInfo()
    case "--git-path":
        gitPath()
    default:
        break
    }
}

// Check for git
guard findGitPath() != nil else {
    print("GitX requires git to be installed.")
    exit(2)
}

// Check for piped input
if isatty(STDIN_FILENO) == 0 {
    handleSTDINDiff()
}

// Get working directory
guard let wdURL = workingDirectoryURL(&arguments) else {
    print("Could not find a git working directory.")
    exit(0)
}

// Handle specific commands
if let first = arguments.first {
    switch first {
    case "--diff", "-d":
        arguments.removeFirst()
        handleDiff(repositoryURL: wdURL, arguments: arguments)
    case "--init":
        arguments.removeFirst()
        handleInit(repositoryURL: wdURL)
    case "--clone":
        arguments.removeFirst()
        handleClone(repositoryURL: wdURL, arguments: arguments)
    default:
        break
    }
}

// Default: open repository
handleOpenRepository(repositoryURL: wdURL, arguments: arguments)
