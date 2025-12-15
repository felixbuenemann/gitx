//
//  RepositoryDocument.swift
//  GitX
//
//  Document representing a Git repository
//

import SwiftUI
import UniformTypeIdentifiers
import libgit2

// MARK: - Repository Document

final class RepositoryDocument: ReferenceFileDocument {
    typealias Snapshot = RepositoryState

    @Published var repository: GitRepository?
    @Published var state: RepositoryState

    static var readableContentTypes: [UTType] { [.folder] }

    init() {
        self.state = RepositoryState()
        Git.initialize()
    }

    init(configuration: ReadConfiguration) throws {
        self.state = RepositoryState()
        Git.initialize()

        guard let url = configuration.file.filename.flatMap({ URL(fileURLWithPath: $0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try loadRepository(at: url)
    }

    func snapshot(contentType: UTType) throws -> RepositoryState {
        return state
    }

    func fileWrapper(snapshot: RepositoryState, configuration: WriteConfiguration) throws -> FileWrapper {
        // Git repositories are read-only from our perspective
        throw CocoaError(.fileWriteNoPermission)
    }

    // MARK: - Repository Loading

    func loadRepository(at url: URL) throws {
        // Find git directory
        let gitDir = findGitDirectory(at: url)

        guard let repoPath = gitDir else {
            throw NSError(
                domain: "GitX",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not a git repository"]
            )
        }

        do {
            repository = try GitRepository(at: repoPath)
            state.url = repoPath
            state.name = repoPath.lastPathComponent
            refreshState()
        } catch {
            throw NSError(
                domain: "GitX",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to open repository",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    private func findGitDirectory(at url: URL) -> URL? {
        var current = url
        let fileManager = FileManager.default

        // If pointing to .git directly
        if current.lastPathComponent == ".git" {
            return current.deletingLastPathComponent()
        }

        // Walk up to find .git
        while current.path != "/" {
            let gitDir = current.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitDir.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }

        return nil
    }

    // MARK: - State Management

    func refreshState() {
        guard let repo = repository else { return }

        Task {
            do {
                // Get current branch
                let head = try repo.head()
                let branchName: String
                if head.isBranch {
                    branchName = head.shortName
                } else {
                    branchName = "HEAD (detached)"
                }

                // Get branches and build ref mapping
                var branchNames: [String] = []
                var commitRefs: [String: [RefInfo]] = [:]

                for branch in try repo.localBranches() {
                    branchNames.append(branch.name)
                    // Get the commit this branch points to
                    let commitOID = branch.targetOID.hex
                    let refInfo = RefInfo(name: branch.name, type: .localBranch)
                    commitRefs[commitOID, default: []].append(refInfo)
                }
                // Sort branches using natural/human sort
                branchNames.sort { $0.localizedStandardCompare($1) == .orderedAscending }

                // Get remote branches
                for branch in try repo.remoteBranches() {
                    let commitOID = branch.targetOID.hex
                    let refInfo = RefInfo(name: branch.name, type: .remoteBranch)
                    commitRefs[commitOID, default: []].append(refInfo)
                }

                // Get remotes
                var remoteNames = try repo.remotes()
                // Sort remotes using natural/human sort
                remoteNames.sort { $0.localizedStandardCompare($1) == .orderedAscending }

                // Get tags
                var tagNames: [String] = []
                for tag in try repo.tags() {
                    tagNames.append(tag.name)
                    // Get the commit this tag points to
                    let commitOID = tag.oid.hex
                    let refInfo = RefInfo(name: tag.name, type: .tag)
                    commitRefs[commitOID, default: []].append(refInfo)
                }
                // Sort tags using natural/human sort (so 0.10.0 comes after 0.9.0)
                tagNames.sort { $0.localizedStandardCompare($1) == .orderedAscending }

                // Get stashes
                var stashInfos: [StashInfo] = []
                if let stashEntries = try? repo.stashes() {
                    for entry in stashEntries {
                        let info = StashInfo(
                            id: entry.index,
                            message: entry.message,
                            date: Date(),  // libgit2 stash doesn't provide date directly
                            stasher: ""    // Would need to look up the commit
                        )
                        stashInfos.append(info)
                    }
                }

                // Get submodules
                let submoduleInfos = self.loadSubmodules()

                // Load commits from selected branch or all
                let commitInfos = loadCommitsSync(fromBranch: state.selectedBranch, limit: 1000)

                await MainActor.run {
                    state.currentBranch = branchName
                    state.branches = branchNames
                    state.remotes = remoteNames
                    state.tags = tagNames
                    state.stashes = stashInfos
                    state.submodules = submoduleInfos
                    state.commits = commitInfos
                    state.commitRefs = commitRefs
                }

            } catch {
                print("Error refreshing state: \(error)")
            }
        }
    }

    // MARK: - Submodule Loading

    /// Parse .gitmodules file and check which submodules are checked out
    private func loadSubmodules() -> [SubmoduleInfo] {
        guard let repoURL = state.url else { return [] }

        let gitmodulesURL = repoURL.appendingPathComponent(".gitmodules")
        guard let content = try? String(contentsOf: gitmodulesURL, encoding: .utf8) else {
            return []
        }

        var submodules: [SubmoduleInfo] = []
        var currentName: String?
        var currentPath: String?
        var currentURL: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[submodule ") {
                // Save previous submodule if complete
                if let name = currentName, let path = currentPath, let url = currentURL {
                    let submodulePath = repoURL.appendingPathComponent(path)
                    let isCheckedOut = isSubmoduleCheckedOut(at: submodulePath)
                    submodules.append(SubmoduleInfo(
                        name: name,
                        path: path,
                        url: url,
                        isCheckedOut: isCheckedOut
                    ))
                }

                // Parse new submodule name
                let start = trimmed.index(trimmed.startIndex, offsetBy: 12) // "[submodule \""
                if let end = trimmed.lastIndex(of: "\"") {
                    currentName = String(trimmed[start..<end])
                }
                currentPath = nil
                currentURL = nil
            } else if trimmed.hasPrefix("path = ") {
                currentPath = String(trimmed.dropFirst(7))
            } else if trimmed.hasPrefix("url = ") {
                currentURL = String(trimmed.dropFirst(6))
            }
        }

        // Don't forget the last submodule
        if let name = currentName, let path = currentPath, let url = currentURL {
            let submodulePath = repoURL.appendingPathComponent(path)
            let isCheckedOut = isSubmoduleCheckedOut(at: submodulePath)
            submodules.append(SubmoduleInfo(
                name: name,
                path: path,
                url: url,
                isCheckedOut: isCheckedOut
            ))
        }

        // Sort submodules using natural/human sort
        submodules.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return submodules
    }

    /// Check if a submodule is checked out by looking for .git in the submodule directory
    private func isSubmoduleCheckedOut(at url: URL) -> Bool {
        let fileManager = FileManager.default
        let gitPath = url.appendingPathComponent(".git").path
        // .git can be a file (gitdir reference) or directory
        return fileManager.fileExists(atPath: gitPath)
    }

    /// Load commits, optionally filtered by branch
    func loadCommits(fromBranch branchName: String?) {
        state.selectedBranch = branchName
        let commits = loadCommitsSync(fromBranch: branchName, limit: 1000)
        state.commits = commits
    }

    private func loadCommitsSync(fromBranch branchName: String? = nil, limit: Int = 1000) -> [CommitInfo] {
        guard let repo = repository else { return [] }

        var commitInfos: [CommitInfo] = []

        do {
            var startOID: GitOID? = nil

            if let branchName = branchName {
                // Find the branch and get its target OID
                if let branch = try repo.localBranches().first(where: { $0.name == branchName }) {
                    startOID = branch.targetOID
                }
            }

            let commits = try repo.log(from: startOID, limit: limit)

            for commit in commits {
                // Get parent IDs
                var parentIds: [String] = []
                for i in 0..<commit.parentCount {
                    if let parentOid = commit.parentOID(at: i) {
                        parentIds.append(parentOid.hex)
                    }
                }

                let info = CommitInfo(
                    oid: commit.oid.hex,
                    shortOID: commit.oid.abbreviated,
                    message: commit.message,
                    summary: commit.summary,
                    author: commit.author.name,
                    authorEmail: commit.author.email,
                    date: commit.author.date,
                    parents: parentIds
                )
                commitInfos.append(info)
            }
        } catch {
            print("Error loading commits: \(error)")
        }

        return commitInfos
    }

    // MARK: - Diff Support

    /// Get the file list for a commit (fast - only deltas, no patch content)
    func getFileList(for commitInfo: CommitInfo) -> DiffResult? {
        guard let repo = repository else { return nil }

        do {
            guard let oid = GitOID(hex: commitInfo.oid) else {
                return nil
            }
            let commit = try repo.lookupCommit(oid: oid)
            let diff = try repo.diff(commit: commit)

            // Only iterate deltas for file metadata - patches are loaded lazily
            var fileChanges: [FileChange] = []

            for index in 0..<diff.deltaCount {
                guard let delta = diff.delta(at: index) else { continue }

                let changeType = convertDeltaStatus(delta.status)

                fileChanges.append(FileChange(
                    path: delta.path,
                    oldPath: delta.oldFile.path,
                    changeType: changeType,
                    hunks: [],  // Empty - loaded lazily
                    isBinary: delta.isBinary,
                    patchIndex: index
                ))
            }

            return DiffResult(files: fileChanges, commitOID: commitInfo.oid)
        } catch {
            print("Error getting file list: \(error)")
            return nil
        }
    }

    /// Get the hunks for a specific file (called when file is selected)
    func getFileHunks(for file: FileChange, commitOID: String) -> [DiffHunk] {
        guard let repo = repository, let patchIndex = file.patchIndex else { return [] }

        do {
            guard let oid = GitOID(hex: commitOID) else { return [] }
            let commit = try repo.lookupCommit(oid: oid)
            let diff = try repo.diff(commit: commit)

            guard let patch = diff.patch(at: patchIndex) else { return [] }

            var hunks: [DiffHunk] = []
            for hunkIndex in 0..<patch.hunkCount {
                guard let hunk = patch.hunk(at: hunkIndex) else { continue }

                var lines: [DiffLine] = []
                for line in hunk.lines {
                    let lineType: DiffLineType
                    if line.isAddition {
                        lineType = .addition
                    } else if line.isDeletion {
                        lineType = .deletion
                    } else {
                        lineType = .context
                    }
                    lines.append(DiffLine(
                        type: lineType,
                        content: line.content,
                        oldLineNumber: lineType == .addition ? nil : line.oldLineNo,
                        newLineNumber: lineType == .deletion ? nil : line.newLineNo
                    ))
                }
                hunks.append(DiffHunk(
                    header: hunk.header,
                    oldStart: hunk.oldStart,
                    oldLines: hunk.oldLines,
                    newStart: hunk.newStart,
                    newLines: hunk.newLines,
                    lines: lines
                ))
            }

            return hunks
        } catch {
            print("Error getting file hunks: \(error)")
            return []
        }
    }

    private func convertDeltaStatus(_ status: git_delta_t) -> FileChangeType {
        switch status {
        case GIT_DELTA_ADDED:
            return .added
        case GIT_DELTA_DELETED:
            return .deleted
        case GIT_DELTA_MODIFIED:
            return .modified
        case GIT_DELTA_RENAMED:
            return .renamed
        case GIT_DELTA_COPIED:
            return .copied
        default:
            return .modified
        }
    }

    /// Get the diff for a commit compared to its parent (legacy - loads everything)
    func getDiff(for commitInfo: CommitInfo) -> DiffResult? {
        guard let repo = repository else { return nil }

        do {
            guard let oid = GitOID(hex: commitInfo.oid) else { return nil }
            let commit = try repo.lookupCommit(oid: oid)
            let diff = try repo.diff(commit: commit)

            var fileChanges: [FileChange] = []

            for index in 0..<diff.deltaCount {
                guard let delta = diff.delta(at: index),
                      let patch = diff.patch(at: index) else { continue }

                var hunks: [DiffHunk] = []
                for hunkIndex in 0..<patch.hunkCount {
                    guard let hunk = patch.hunk(at: hunkIndex) else { continue }

                    var lines: [DiffLine] = []
                    for line in hunk.lines {
                        let lineType: DiffLineType
                        if line.isAddition {
                            lineType = .addition
                        } else if line.isDeletion {
                            lineType = .deletion
                        } else {
                            lineType = .context
                        }
                        lines.append(DiffLine(
                            type: lineType,
                            content: line.content,
                            oldLineNumber: lineType == .addition ? nil : line.oldLineNo,
                            newLineNumber: lineType == .deletion ? nil : line.newLineNo
                        ))
                    }
                    hunks.append(DiffHunk(
                        header: hunk.header,
                        oldStart: hunk.oldStart,
                        oldLines: hunk.oldLines,
                        newStart: hunk.newStart,
                        newLines: hunk.newLines,
                        lines: lines
                    ))
                }

                let changeType = convertDeltaStatus(delta.status)

                fileChanges.append(FileChange(
                    path: delta.path,
                    oldPath: delta.oldFile.path,
                    changeType: changeType,
                    hunks: hunks,
                    isBinary: delta.isBinary
                ))
            }

            return DiffResult(files: fileChanges)
        } catch {
            print("Error getting diff: \(error)")
            return nil
        }
    }

    /// Get file content at a specific commit
    func getFileContent(path: String, at commitInfo: CommitInfo) -> String? {
        guard let repo = repository else { return nil }

        do {
            guard let oid = GitOID(hex: commitInfo.oid) else { return nil }
            let commit = try repo.lookupCommit(oid: oid)
            let tree = try commit.tree(in: repo)

            // Find the blob in the tree by searching entries
            let pathComponents = path.components(separatedBy: "/")
            var currentTree = tree

            for (index, component) in pathComponents.enumerated() {
                var foundEntry: GitTreeEntry? = nil
                for entryIndex in 0..<currentTree.entryCount {
                    if let entry = currentTree.entry(at: entryIndex), entry.name == component {
                        foundEntry = entry
                        break
                    }
                }

                guard let entry = foundEntry else { return nil }

                if index == pathComponents.count - 1 {
                    // This is the file - load the blob
                    if entry.isBlob {
                        let data = try repo.lookupBlob(oid: entry.oid)
                        return String(data: data, encoding: .utf8)
                    }
                } else {
                    // This is a directory - load the subtree
                    if entry.isTree {
                        currentTree = try repo.lookupTree(oid: entry.oid)
                    }
                }
            }
        } catch {
            print("Error getting file content: \(error)")
        }
        return nil
    }
}

// MARK: - Diff View Models

struct DiffResult {
    let files: [FileChange]
    var commitOID: String?
}

struct FileChange: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let oldPath: String
    let changeType: FileChangeType
    var hunks: [DiffHunk]
    let isBinary: Bool
    var patchIndex: Int?

    var displayPath: String {
        if changeType == .renamed && oldPath != path {
            return "\(oldPath) → \(path)"
        }
        return path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: FileChange, rhs: FileChange) -> Bool {
        lhs.path == rhs.path
    }
}

enum FileChangeType {
    case added
    case deleted
    case modified
    case renamed
    case copied

    var symbol: String {
        switch self {
        case .added: return "A"
        case .deleted: return "D"
        case .modified: return "M"
        case .renamed: return "R"
        case .copied: return "C"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .deleted: return .red
        case .modified: return .orange
        case .renamed: return .purple
        case .copied: return .blue
        }
    }
}

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum DiffLineType {
    case context
    case addition
    case deletion

    var prefix: String {
        switch self {
        case .context: return " "
        case .addition: return "+"
        case .deletion: return "-"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .context: return .clear
        case .addition: return Color.green.opacity(0.2)
        case .deletion: return Color.red.opacity(0.2)
        }
    }

    var textColor: Color {
        switch self {
        case .context: return .primary
        case .addition: return .green
        case .deletion: return .red
        }
    }
}

// MARK: - Repository State

struct RepositoryState {
    var url: URL?
    var name: String = ""
    var currentBranch: String = ""
    var selectedBranch: String? = nil  // nil means show all/HEAD
    var branches: [String] = []
    var remotes: [String] = []
    var tags: [String] = []
    var stashes: [StashInfo] = []
    var submodules: [SubmoduleInfo] = []
    var commits: [CommitInfo] = []
    var selectedCommit: CommitInfo?
    var commitRefs: [String: [RefInfo]] = [:]  // OID -> refs pointing to it
}

// MARK: - Submodule Info

struct SubmoduleInfo: Identifiable, Hashable {
    let name: String
    let path: String
    let url: String
    let isCheckedOut: Bool

    var id: String { name }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: SubmoduleInfo, rhs: SubmoduleInfo) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Stash Info

struct StashInfo: Identifiable, Hashable {
    let id: Int  // stash index
    let message: String
    let date: Date
    let stasher: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StashInfo, rhs: StashInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct RefInfo: Hashable {
    let name: String
    let type: RefType

    enum RefType {
        case localBranch
        case remoteBranch
        case tag
    }
}

// MARK: - Commit Info

struct CommitInfo: Identifiable, Hashable {
    let id = UUID()
    let oid: String
    let shortOID: String
    let message: String
    let summary: String
    let author: String
    let authorEmail: String
    let date: Date
    let parents: [String]

    func hash(into hasher: inout Hasher) {
        hasher.combine(oid)
    }

    static func == (lhs: CommitInfo, rhs: CommitInfo) -> Bool {
        lhs.oid == rhs.oid
    }
}
