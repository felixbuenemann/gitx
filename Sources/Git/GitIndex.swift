//
//  GitIndex.swift
//  GitX
//
//  Swift conversion of PBGitIndex
//  Original by Pieter de Bie on 9/12/09
//

import Foundation
import Combine

// MARK: - Notifications

public extension Notification.Name {
    static let gitIndexRefreshStatus = Notification.Name("PBGitIndexIndexRefreshStatus")
    static let gitIndexRefreshFailed = Notification.Name("PBGitIndexIndexRefreshFailed")
    static let gitIndexFinishedRefresh = Notification.Name("PBGitIndexFinishedIndexRefresh")
    static let gitIndexUpdated = Notification.Name("GBGitIndexIndexUpdated")
    static let gitIndexCommitStatus = Notification.Name("PBGitIndexCommitStatus")
    static let gitIndexCommitFailed = Notification.Name("PBGitIndexCommitFailed")
    static let gitIndexCommitHookFailed = Notification.Name("PBGitIndexCommitHookFailed")
    static let gitIndexFinishedCommit = Notification.Name("PBGitIndexFinishedCommit")
    static let gitIndexAmendMessageAvailable = Notification.Name("PBGitIndexAmendMessageAvailable")
    static let gitIndexOperationFailed = Notification.Name("PBGitIndexOperationFailed")
}

// MARK: - Changed File Status

@objc public enum ChangedFileStatus: Int {
    case new = 0
    case modified = 1
    case deleted = 2
}

// MARK: - Changed File

@objc public class ChangedFile: NSObject {
    @objc public var path: String
    @objc public var status: ChangedFileStatus = .modified
    @objc public var hasStagedChanges: Bool = false
    @objc public var hasUnstagedChanges: Bool = false
    @objc public var commitBlobSHA: String = ""
    @objc public var commitBlobMode: String = ""

    @objc public init(path: String) {
        self.path = path
        super.init()
    }

    @objc public var indexInfo: String {
        // Format for git update-index --index-info
        return "\(commitBlobMode) \(commitBlobSHA)\t\(path)\0"
    }
}

// MARK: - Git Index

@objc public class GitIndex: NSObject {

    @objc public weak var repository: GitRepository?
    @objc public var workingDirectory: URL?

    @objc public private(set) var files: [ChangedFile] = []

    private var refreshStatus: Int = 0
    private var amendEnvironment: [String: String]?

    @objc public var amend: Bool = false {
        didSet {
            if amend != oldValue {
                amendEnvironment = nil
                refresh()

                if amend {
                    loadAmendInfo()
                }
            }
        }
    }

    @objc public var indexChanges: [ChangedFile] {
        return files
    }

    @objc public init(repository: GitRepository) {
        self.repository = repository
        if let workDir = repository.workingDirectory {
            self.workingDirectory = URL(fileURLWithPath: workDir)
        }
        super.init()
    }

    // MARK: - Refresh

    @objc public func refresh() {
        refreshStatus = 0
        files.removeAll()

        guard let workDir = workingDirectory?.path,
              let gitPath = GitBinary.path else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performRefresh(gitPath: gitPath, workDir: workDir)
        }
    }

    private func performRefresh(gitPath: String, workDir: String) {
        // Update index
        do {
            _ = try EasyPipe.output(
                for: gitPath,
                arguments: ["update-index", "-q", "--unmerged", "--ignore-missing", "--refresh"],
                directory: workDir
            )
        } catch {
            postNotification(.gitIndexRefreshFailed, description: "update-index failed")
            return
        }

        guard repository?.isBareRepository == false else { return }

        // Read other files (untracked)
        readOtherFiles(gitPath: gitPath, workDir: workDir)

        // Read unstaged files
        readUnstagedFiles(gitPath: gitPath, workDir: workDir)

        // Read staged files
        readStagedFiles(gitPath: gitPath, workDir: workDir)

        postNotification(.gitIndexFinishedRefresh)
        postNotification(.gitIndexUpdated)
    }

    private func readOtherFiles(gitPath: String, workDir: String) {
        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["ls-files", "--others", "--exclude-standard", "-z"],
                directory: workDir
            )

            let paths = result.output.components(separatedBy: "\0").filter { !$0.isEmpty }
            for path in paths {
                let file = ChangedFile(path: path)
                file.status = .new
                file.hasUnstagedChanges = true
                file.hasStagedChanges = false
                files.append(file)
            }
        } catch {}
    }

    private func readUnstagedFiles(gitPath: String, workDir: String) {
        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["diff-files", "-z"],
                directory: workDir
            )

            parseFilesFromDiff(result.output, staged: false)
        } catch {}
    }

    private func readStagedFiles(gitPath: String, workDir: String) {
        do {
            let parentTree = amend ? "HEAD^" : "HEAD"
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["diff-index", "--cached", "-z", parentTree],
                directory: workDir
            )

            parseFilesFromDiff(result.output, staged: true)
        } catch {}
    }

    private func parseFilesFromDiff(_ output: String, staged: Bool) {
        let parts = output.components(separatedBy: "\0").filter { !$0.isEmpty }
        var i = 0
        while i < parts.count - 1 {
            let status = parts[i]
            let path = parts[i + 1]
            i += 2

            let statusParts = status.components(separatedBy: " ")
            guard statusParts.count >= 5 else { continue }

            let file: ChangedFile
            if let existing = files.first(where: { $0.path == path }) {
                file = existing
            } else {
                file = ChangedFile(path: path)
                files.append(file)
            }

            file.commitBlobMode = String(statusParts[0].dropFirst()) // Remove leading ':'
            file.commitBlobSHA = statusParts[2]

            if staged {
                file.hasStagedChanges = true
            } else {
                file.hasUnstagedChanges = true
            }

            if statusParts[4] == "D" {
                file.status = .deleted
            } else if statusParts[0] == ":000000" {
                file.status = .new
            } else {
                file.status = .modified
            }
        }
    }

    // MARK: - Commit

    @objc public func commit(message: String, verify: Bool) {
        guard let repo = repository,
              let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else {
            postCommitFailure("Repository not available")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performCommit(message: message, verify: verify, repo: repo, gitPath: gitPath, workDir: workDir)
        }
    }

    private func performCommit(message: String, verify: Bool, repo: GitRepository, gitPath: String, workDir: String) {
        let commitMessageFile = (repo.gitURL?.path ?? "") + "/COMMIT_EDITMSG"

        do {
            try message.write(toFile: commitMessageFile, atomically: true, encoding: .utf8)
        } catch {
            postCommitFailure("Could not write commit message")
            return
        }

        postCommitUpdate("Creating tree")

        do {
            let treeResult = try EasyPipe.output(
                for: gitPath,
                arguments: ["write-tree"],
                directory: workDir
            )

            let tree = treeResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tree.count == 40 else {
                postCommitFailure("Creating tree failed")
                return
            }

            // Run hooks if verify is true
            if verify {
                postCommitUpdate("Running hooks")

                let preCommitResult = try EasyPipe.output(
                    for: gitPath,
                    arguments: ["hook", "run", "pre-commit"],
                    directory: workDir
                )

                if preCommitResult.exitCode != 0 {
                    postCommitHookFailure("Pre-commit hook failed: \(preCommitResult.output)")
                    return
                }
            }

            // Create commit
            postCommitUpdate("Creating commit")

            var commitArgs = ["commit-tree", tree]

            let parentTree = amend ? "HEAD^" : "HEAD"
            let parentResult = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--verify", parentTree],
                directory: workDir
            )

            if parentResult.exitCode == 0 {
                commitArgs.append("-p")
                commitArgs.append(parentTree)
            }

            let commitResult = try EasyPipe.output(
                for: gitPath,
                arguments: commitArgs,
                directory: workDir,
                environment: amendEnvironment,
                input: message
            )

            let commitSha = commitResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard commitSha.count == 40 else {
                postCommitFailure("Could not create a commit object")
                return
            }

            // Update HEAD
            postCommitUpdate("Updating HEAD")

            let subject = "commit: " + (message.components(separatedBy: "\n").first ?? message)
            let updateResult = try EasyPipe.output(
                for: gitPath,
                arguments: ["update-ref", "-m", subject, "HEAD", commitSha],
                directory: workDir
            )

            guard updateResult.exitCode == 0 else {
                postCommitFailure("Could not update HEAD")
                return
            }

            // Run post-commit hook
            postCommitUpdate("Running post-commit hook")

            DispatchQueue.main.async { [weak self] in
                NotificationCenter.default.post(
                    name: .gitIndexFinishedCommit,
                    object: self,
                    userInfo: [
                        "success": true,
                        "description": "Successfully created commit \(commitSha)",
                        "sha": commitSha
                    ]
                )
            }

            if amend {
                amend = false
            } else {
                refresh()
            }

        } catch {
            postCommitFailure("Commit failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stage/Unstage

    @objc public func stageFiles(_ filesToStage: [ChangedFile]) -> Bool {
        guard let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return false }

        let input = filesToStage.map { $0.path }.joined(separator: "\0")

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["update-index", "--add", "--remove", "-z", "--stdin"],
                directory: workDir,
                input: input
            )

            if result.exitCode != 0 {
                postOperationFailed("Error in staging files. Return value: \(result.exitCode)")
                return false
            }

            for file in filesToStage {
                file.hasUnstagedChanges = false
                file.hasStagedChanges = true
            }

            postNotification(.gitIndexUpdated)
            return true
        } catch {
            return false
        }
    }

    @objc public func unstageFiles(_ filesToUnstage: [ChangedFile]) -> Bool {
        guard let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return false }

        let input = filesToUnstage.map { $0.indexInfo }.joined()

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["update-index", "-z", "--index-info"],
                directory: workDir,
                input: input
            )

            if result.exitCode != 0 {
                postOperationFailed("Error in unstaging files. Return value: \(result.exitCode)")
                return false
            }

            for file in filesToUnstage {
                file.hasUnstagedChanges = true
                file.hasStagedChanges = false
            }

            postNotification(.gitIndexUpdated)
            return true
        } catch {
            return false
        }
    }

    @objc public func discardChanges(for filesToDiscard: [ChangedFile]) {
        guard let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return }

        let input = filesToDiscard.map { $0.path }.joined(separator: "\0")

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["checkout-index", "--index", "--quiet", "--force", "-z", "--stdin"],
                directory: workDir,
                input: input
            )

            if result.exitCode != 0 {
                postOperationFailed("Discarding changes failed with return value \(result.exitCode)")
                return
            }

            for file in filesToDiscard {
                if file.status != .new {
                    file.hasUnstagedChanges = false
                }
            }

            postNotification(.gitIndexUpdated)
        } catch {}
    }

    // MARK: - Patch

    @objc public func applyPatch(_ hunk: String, stage: Bool, reverse: Bool) -> Bool {
        guard let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return false }

        var args = ["apply", "--unidiff-zero"]
        if stage { args.append("--cached") }
        if reverse { args.append("--reverse") }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: args,
                directory: workDir,
                input: hunk
            )

            if result.exitCode != 0 {
                postOperationFailed("Applying patch failed with return value \(result.exitCode). Error: \(result.output)")
                return false
            }

            refresh()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Diff

    @objc public func diff(for file: ChangedFile, staged: Bool, contextLines: Int = 3) -> String? {
        guard let repo = repository,
              let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return nil }

        let parameter = "-U\(contextLines)"

        do {
            if staged {
                if file.status == .new {
                    let indexPath = ":0:\(file.path)"
                    let result = try EasyPipe.output(
                        for: gitPath,
                        arguments: ["show", indexPath],
                        directory: workDir
                    )
                    return result.output
                }

                let parentTree = amend ? "HEAD^" : "HEAD"
                let result = try EasyPipe.output(
                    for: gitPath,
                    arguments: ["diff-index", parameter, "--cached", parentTree, "--", file.path],
                    directory: workDir
                )
                return result.output
            } else {
                if file.status == .new {
                    let filePath = (repo.workingDirectory ?? "") + "/" + file.path
                    return try? String(contentsOfFile: filePath, encoding: .utf8)
                }

                let result = try EasyPipe.output(
                    for: gitPath,
                    arguments: ["diff-files", parameter, "--", file.path],
                    directory: workDir
                )
                return result.output
            }
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func loadAmendInfo() {
        guard let repo = repository,
              let gitPath = GitBinary.path,
              let workDir = workingDirectory?.path else { return }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["cat-file", "commit", "HEAD"],
                directory: workDir
            )

            let message = result.output

            // Extract author info for amend
            let pattern = "\nauthor ([^\n]*) <([^\n>]*)> ([0-9]+[^\n]*)\n"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
                if let nameRange = Range(match.range(at: 1), in: message),
                   let emailRange = Range(match.range(at: 2), in: message),
                   let dateRange = Range(match.range(at: 3), in: message) {
                    amendEnvironment = [
                        "GIT_AUTHOR_NAME": String(message[nameRange]),
                        "GIT_AUTHOR_EMAIL": String(message[emailRange]),
                        "GIT_AUTHOR_DATE": String(message[dateRange])
                    ]
                }
            }

            // Find commit message
            if let range = message.range(of: "\n\n") {
                let commitMessage = String(message[range.upperBound...])
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .gitIndexAmendMessageAvailable,
                        object: self,
                        userInfo: ["message": commitMessage]
                    )
                }
            }
        } catch {}
    }

    private func postNotification(_ name: Notification.Name, description: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            var userInfo: [String: Any] = [:]
            if let desc = description {
                userInfo["description"] = desc
            }
            NotificationCenter.default.post(name: name, object: self, userInfo: userInfo.isEmpty ? nil : userInfo)
        }
    }

    private func postCommitUpdate(_ update: String) {
        postNotification(.gitIndexCommitStatus, description: update)
    }

    private func postCommitFailure(_ reason: String) {
        postNotification(.gitIndexCommitFailed, description: reason)
    }

    private func postCommitHookFailure(_ reason: String) {
        postNotification(.gitIndexCommitHookFailed, description: reason)
    }

    private func postOperationFailed(_ description: String) {
        postNotification(.gitIndexOperationFailed, description: description)
    }
}
