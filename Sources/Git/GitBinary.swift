//
//  GitBinary.swift
//  GitX
//
//  Swift conversion of PBGitBinary
//  Original by Pieter de Bie on 04-10-08
//

import Foundation

public enum GitBinary {

    public static let minimumVersion = "1.6.0"

    private static var cachedPath: String?
    private static var cachedVersion: String?

    public static var path: String? {
        if cachedPath == nil {
            initialize()
        }
        return cachedPath
    }

    public static var version: String? {
        guard let path = path else { return nil }
        return versionForPath(path)
    }

    public static var searchLocations: [String] {
        var locations = [
            "/opt/local/bin/git",
            "/sw/bin/git",
            "/opt/git/bin/git",
            "/usr/local/bin/git",
            "/usr/local/git/bin/git",
            "/opt/homebrew/bin/git"
        ]

        let homeGit = ("~/bin/git" as NSString).expandingTildeInPath
        locations.append(homeGit)
        locations.append("/usr/bin/git")

        return locations
    }

    public static var notFoundError: String {
        var error = """
        Could not find a git binary version \(minimumVersion) or higher.
        Please make sure there is a git binary in one of the following locations:

        """
        for location in searchLocations {
            error += "\t\(location)\n"
        }
        return error
    }

    // MARK: - Private Methods

    private static func versionForPath(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        do {
            let result = try EasyPipe.output(for: path, arguments: ["--version"])
            let version = result.output
            if version.hasPrefix("git version ") {
                return String(version.dropFirst(12))
            }
        } catch {
            return nil
        }

        return nil
    }

    private static func acceptBinary(_ path: String) -> Bool {
        guard let version = versionForPath(path) else { return false }

        let comparison = version.compare(minimumVersion, options: .numeric)
        if comparison == .orderedSame || comparison == .orderedDescending {
            cachedPath = path
            cachedVersion = version
            return true
        }

        print("Found a git binary at \(path), but is only version \(version)")
        return false
    }

    private static func initialize() {
        // Check user defaults first
        if let userPath = UserDefaults.standard.string(forKey: "gitExecutable"),
           !userPath.isEmpty,
           acceptBinary(userPath) {
            return
        }

        // Check GIT_PATH environment variable
        if let envPath = ProcessInfo.processInfo.environment["GIT_PATH"],
           acceptBinary(envPath) {
            return
        }

        // Try to find git with "which"
        do {
            let result = try EasyPipe.output(for: "/usr/bin/which", arguments: ["git"])
            let whichPath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if acceptBinary(whichPath) {
                return
            }
        } catch {}

        // Try default locations
        for location in searchLocations {
            if acceptBinary(location) {
                return
            }
        }

        // Try xcrun git
        do {
            let result = try EasyPipe.output(for: "/usr/bin/xcrun", arguments: ["-f", "git"])
            let xcrunPath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if acceptBinary(xcrunPath) {
                return
            }
        } catch {}

        print("Could not find a git binary higher than version \(minimumVersion)")
    }
}
