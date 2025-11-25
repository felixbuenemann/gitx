//
//  GitRepository.swift
//  GitX
//
//  Swift conversion of PBGitRepository
//  Original by Pieter de Bie on 13-06-08
//

import AppKit

public let GitRepositoryErrorDomain = "GitRepositoryErrorDomain"
public let GitRepositoryDocumentType = "Git Repository"

public enum BranchFilterType: Int {
    case all = 0
    case localRemote = 1
    case selected = 2

    public var description: String {
        switch self {
        case .all: return "All"
        case .localRemote: return "Local"
        case .selected: return "Selected"
        }
    }
}

@objc public class GitRepository: NSDocument {

    // MARK: - Properties

    @objc public var hasChanged: Bool = false
    @objc public var currentBranchFilter: Int = 0

    @objc public private(set) var windowController: RepositoryWindowController?
    @objc public lazy var revisionList: GitHistoryList = {
        return GitHistoryList(repository: self)
    }()

    @objc public var branches: [GitRevSpecifier] = []
    @objc public var currentBranch: GitRevSpecifier?
    @objc public var refs: [String: [GitRef]] = [:]
    @objc public var submodules: [Any] = []

    @objc public private(set) var gitURL: URL?
    private var _headRef: GitRevSpecifier?
    private var _headSHA: String?

    private var watcher: GitRepositoryWatcher?

    // MARK: - Initialization

    public override init() {
        currentBranchFilter = GitDefaults.branchFilter
        super.init()
    }

    // MARK: - Document API

    public override func read(from url: URL, ofType typeName: String) throws {
        guard let gitPath = GitBinary.path else {
            throw NSError(
                domain: GitRepositoryErrorDomain,
                code: 0,
                userInfo: [NSLocalizedRecoverySuggestionErrorKey: GitBinary.notFoundError]
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(
                domain: GitRepositoryErrorDomain,
                code: 0,
                userInfo: [NSLocalizedRecoverySuggestionErrorKey: "Reading files is not supported."]
            )
        }

        gitURL = GitRepoFinder.gitDir(for: url)
        guard gitURL != nil else {
            throw NSError(
                domain: GitRepositoryErrorDomain,
                code: 0,
                userInfo: [NSLocalizedRecoverySuggestionErrorKey: "\(url.path) does not appear to be a git repository."]
            )
        }

        reloadRefs()

        // Setup file system watcher
        if GitDefaults.useRepositoryWatcher {
            watcher = GitRepositoryWatcher(repository: self)
        }
    }

    public override func close() {
        watcher?.stop()
        super.close()
    }

    public override var isDocumentEdited: Bool {
        return false
    }

    public override var displayName: String! {
        get {
            if isHEADDetached {
                return String(format: NSLocalizedString("%@ (detached HEAD)", comment: ""), projectName)
            }
            return String(format: NSLocalizedString("%@ (branch: %@)", comment: ""), projectName, headRef?.description ?? "")
        }
        set { super.displayName = newValue }
    }

    public override func makeWindowControllers() {
        #if !CLI
        let controller = RepositoryWindowController(repository: self, displayDefault: true)
        windowController = controller
        addWindowController(controller)
        #endif
    }

    // MARK: - Repository Info

    @objc public var workingDirectory: String? {
        guard let gitPath = GitBinary.path, let gitDir = gitURL?.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--show-toplevel"],
                directory: gitDir
            )
            if result.exitCode == 0 {
                return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}

        return fileURL?.path
    }

    @objc public var projectName: String {
        return (workingDirectory as NSString?)?.lastPathComponent ?? "Unknown"
    }

    @objc public var gitIgnoreFilename: String {
        return (workingDirectory ?? "") + "/.gitignore"
    }

    @objc public var isBareRepository: Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--is-bare-repository"],
                directory: dir
            )
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    @objc public var isHEADDetached: Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["symbolic-ref", "-q", "HEAD"],
                directory: dir
            )
            return result.exitCode != 0
        } catch {
            return false
        }
    }

    @objc public var hasSVNRemote: Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["config", "--get-regexp", "^svn-remote\\."],
                directory: dir
            )
            return result.exitCode == 0 && !result.output.isEmpty
        } catch {
            return false
        }
    }

    @objc public var indexURL: URL? {
        return gitURL?.appendingPathComponent("index")
    }

    // MARK: - Refs

    @objc public func reloadRefs() {
        _headRef = nil
        _headSHA = nil
        refs = [:]

        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return }

        do {
            // Get all refs
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["for-each-ref", "--format=%(refname) %(objectname)"],
                directory: dir
            )

            var oldBranches = Set(branches)

            for line in result.output.components(separatedBy: "\n") where !line.isEmpty {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let refName = parts[0]
                let sha = parts[1]

                let gitRef = GitRef(string: refName)
                let revSpec = GitRevSpecifier(ref: gitRef)

                addBranch(revSpec)
                addRef(gitRef, for: sha)

                oldBranches.remove(revSpec)
            }

            // Remove old branches
            for branch in oldBranches {
                if branch.isSimpleRef && branch != headRef {
                    removeBranch(branch)
                }
            }

            windowController?.window?.title = displayName

        } catch {}
    }

    @objc public func lazyReload() {
        guard hasChanged else { return }
        revisionList.updateHistory()
        hasChanged = false
    }

    @objc public var headRef: GitRevSpecifier? {
        if let cached = _headRef {
            return cached
        }

        guard let branch = parseSymbolicReference("HEAD") else {
            _headRef = GitRevSpecifier(ref: GitRef(string: "HEAD"))
            return _headRef
        }

        if branch.hasPrefix("refs/heads/") {
            _headRef = GitRevSpecifier(ref: GitRef(string: branch))
        } else {
            _headRef = GitRevSpecifier(ref: GitRef(string: "HEAD"))
        }

        if let ref = _headRef?.ref {
            _headSHA = sha(for: ref)
        }

        return _headRef
    }

    @objc public var headSHA: String? {
        if _headSHA == nil {
            _ = headRef
        }
        return _headSHA
    }

    @objc public var headCommit: GitCommit? {
        guard let sha = headSHA else { return nil }
        return commitForSHA(sha)
    }

    // MARK: - Ref Operations

    @objc public func sha(for ref: GitRef) -> String? {
        // Check cache first
        for (sha, refsForSHA) in refs {
            if refsForSHA.contains(where: { $0.isEqualToRef(ref) }) {
                return sha
            }
        }

        // Look up in repository
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--verify", ref.ref],
                directory: dir
            )
            if result.exitCode == 0 {
                return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}

        return nil
    }

    @objc public func commit(for ref: GitRef) -> GitCommit? {
        guard let sha = sha(for: ref) else { return nil }
        return commitForSHA(sha)
    }

    @objc public func commitForSHA(_ sha: String) -> GitCommit? {
        return revisionList.projectCommits.first { $0.sha == sha }
    }

    private func addRef(_ ref: GitRef, for sha: String) {
        if refs[sha] == nil {
            refs[sha] = [ref]
        } else {
            if !refs[sha]!.contains(where: { $0.isEqualToRef(ref) }) {
                refs[sha]!.append(ref)
            }
        }
    }

    // MARK: - Branch Operations

    @discardableResult
    @objc public func addBranch(_ branch: GitRevSpecifier) -> GitRevSpecifier {
        var branchToAdd = branch
        if branch.parameters.isEmpty {
            branchToAdd = headRef ?? branch
        }

        if !branches.contains(branchToAdd) {
            branches.append(branchToAdd)
        }

        return branchToAdd
    }

    @objc public func removeBranch(_ branch: GitRevSpecifier) -> Bool {
        if let index = branches.firstIndex(of: branch) {
            branches.remove(at: index)
            return true
        }
        return false
    }

    @objc public func readCurrentBranch() {
        if let head = headRef {
            currentBranch = addBranch(head)
        }
    }

    // MARK: - Branch Checking

    @objc public func isOnSameBranch(_ baseSHA: String, as testSHA: String) -> Bool {
        // Simplified implementation
        if baseSHA == testSHA { return true }
        // Full implementation would traverse commit graph
        return false
    }

    @objc public func isSHAOnHeadBranch(_ testSHA: String) -> Bool {
        guard let headSHA = headSHA else { return false }
        if testSHA == headSHA { return true }
        return isOnSameBranch(headSHA, as: testSHA)
    }

    @objc public func isRefOnHeadBranch(_ testRef: GitRef) -> Bool {
        guard let sha = sha(for: testRef) else { return false }
        return isSHAOnHeadBranch(sha)
    }

    // MARK: - Ref Validation

    @objc public func checkRefFormat(_ refName: String) -> Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["check-ref-format", refName],
                directory: dir
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    @objc public func refExists(_ ref: GitRef) -> Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["show-ref", "--verify", "--quiet", ref.ref],
                directory: dir
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    @objc public func ref(for name: String) -> GitRef? {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["show-ref", name],
                directory: dir
            )
            if result.exitCode == 0 {
                let lines = result.output.components(separatedBy: .whitespacesAndNewlines)
                if lines.count > 1 {
                    return GitRef(string: lines[1])
                }
            }
        } catch {}

        return nil
    }

    // MARK: - Remotes

    @objc public var remotes: [String]? {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["remote"],
                directory: dir
            )
            if result.exitCode == 0 && !result.output.isEmpty {
                return result.output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            }
        } catch {}

        return nil
    }

    @objc public var hasRemotes: Bool {
        return remotes != nil && !remotes!.isEmpty
    }

    @objc public func infoForRemote(_ remoteName: String) -> String? {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["remote", "show", remoteName],
                directory: dir
            )
            if result.exitCode == 0 {
                return result.output
            }
        } catch {}

        return nil
    }

    // MARK: - Git Operations

    @objc public func checkout(refish: GitRefish) -> Bool {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return false }

        let refName: String
        if refish.refishType == GitRefType.branch.rawValue {
            refName = refish.shortName
        } else {
            refName = refish.refishName
        }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["checkout", refName],
                directory: dir
            )

            if result.exitCode != 0 {
                windowController?.showErrorSheet(
                    title: "Checkout failed!",
                    message: "There was an error checking out the \(refish.refishType) '\(refish.shortName)'.\n\nPerhaps your working directory is not clean?",
                    output: result.output
                )
                return false
            }

            reloadRefs()
            readCurrentBranch()
            return true
        } catch {
            return false
        }
    }

    @objc public func merge(with refish: GitRefish) -> Bool {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["merge", refish.refishName],
                directory: dir
            )

            if result.exitCode != 0 {
                let headName = headRef?.ref?.shortName ?? "HEAD"
                windowController?.showErrorSheet(
                    title: "Merge failed!",
                    message: "There was an error merging \(refish.refishName) into \(headName).",
                    output: result.output
                )
                return false
            }

            reloadRefs()
            readCurrentBranch()
            return true
        } catch {
            return false
        }
    }

    @objc public func createBranch(_ branchName: String, at refish: GitRefish) -> Bool {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["branch", branchName, refish.refishName],
                directory: dir
            )

            if result.exitCode != 0 {
                windowController?.showErrorSheet(
                    title: "Create Branch failed!",
                    message: "There was an error creating the branch '\(branchName)' at \(refish.refishType) '\(refish.shortName)'.",
                    output: result.output
                )
                return false
            }

            reloadRefs()
            return true
        } catch {
            return false
        }
    }

    @objc public func createTag(_ tagName: String, message: String?, at refish: GitRefish) -> Bool {
        guard let gitPath = GitBinary.path, let dir = workingDirectory else { return false }

        var args = ["tag"]
        if let msg = message, !msg.isEmpty {
            args.append(contentsOf: ["-a", "-m", msg])
        }
        args.append(tagName)
        args.append(refish.refishName)

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: args,
                directory: dir
            )

            if result.exitCode != 0 {
                windowController?.showErrorSheet(
                    title: "Create Tag failed!",
                    message: "There was an error creating the tag '\(tagName)'.",
                    output: result.output
                )
                return false
            }

            reloadRefs()
            return true
        } catch {
            return false
        }
    }

    @objc public func deleteRef(_ ref: GitRef) -> Bool {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return false }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["update-ref", "-d", ref.ref],
                directory: dir
            )

            if result.exitCode != 0 {
                windowController?.showErrorSheet(
                    title: "Delete ref failed!",
                    message: "There was an error deleting the ref: \(ref.shortName)",
                    output: result.output
                )
                return false
            }

            removeBranch(GitRevSpecifier(ref: ref))
            commit(for: ref)?.removeRef(ref)
            reloadRefs()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Git Parsing

    @objc public func parseReference(_ reference: String) -> String? {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--verify", reference],
                directory: dir
            )
            if result.exitCode == 0 {
                return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}

        return nil
    }

    @objc public func parseSymbolicReference(_ reference: String) -> String? {
        guard let gitPath = GitBinary.path, let dir = fileURL?.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["symbolic-ref", "-q", reference],
                directory: dir
            )
            let ref = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if ref.hasPrefix("refs/") {
                return ref
            }
        } catch {}

        return nil
    }

    // MARK: - Hook Execution

    @objc public func executeHook(_ name: String, arguments: [String] = []) -> HookExecutionResult {
        guard let hookPath = gitURL?.appendingPathComponent("hooks/\(name)").path,
              FileManager.default.isExecutableFile(atPath: hookPath),
              let dir = workingDirectory,
              let gitDir = gitURL?.path else {
            return HookExecutionResult(success: true, output: nil)  // No hook is success
        }

        let environment = [
            "GIT_DIR": gitDir,
            "GIT_INDEX_FILE": gitDir + "/index"
        ]

        do {
            let result = try EasyPipe.output(
                for: hookPath,
                arguments: arguments,
                directory: dir,
                environment: environment
            )
            return HookExecutionResult(success: result.exitCode == 0, output: result.output)
        } catch {
            return HookExecutionResult(success: false, output: error.localizedDescription)
        }
    }

    // MARK: - Force Update

    @objc public func forceUpdateRevisions() {
        revisionList.forceUpdate()
    }
}

// MARK: - Git Repo Finder

public enum GitRepoFinder {
    public static func gitDir(for url: URL) -> URL? {
        guard let gitPath = GitBinary.path else { return nil }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["rev-parse", "--git-dir"],
                directory: url.path
            )

            if result.exitCode == 0 {
                let gitDir = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if gitDir.hasPrefix("/") {
                    return URL(fileURLWithPath: gitDir)
                } else {
                    return url.appendingPathComponent(gitDir)
                }
            }
        } catch {}

        return nil
    }
}

// MARK: - Placeholder Classes

@objc public class GitHistoryList: NSObject {
    @objc public weak var repository: GitRepository?
    @objc public var projectCommits: [GitCommit] = []

    @objc public init(repository: GitRepository) {
        self.repository = repository
        super.init()
    }

    @objc public func updateHistory() {
        forceUpdate()
    }

    @objc public func forceUpdate() {
        // Load commits from git log
        guard let repo = repository,
              let gitPath = GitBinary.path,
              let dir = repo.fileURL?.path else { return }

        do {
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: [
                    "log",
                    "--all",
                    "--format=%H|%h|%at|%s|%an|%ae|%cn|%ce|%P",
                    "-1000"
                ],
                directory: dir
            )

            var commits: [GitCommit] = []

            for line in result.output.components(separatedBy: "\n") where !line.isEmpty {
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 8 else { continue }

                let sha = parts[0]
                let shortSHA = parts[1]
                let timestamp = TimeInterval(parts[2]) ?? 0
                let subject = parts[3]
                let author = parts[4]
                let authorEmail = parts[5]
                let committer = parts[6]
                let committerEmail = parts[7]
                let parentSHAs = parts.count > 8 ? parts[8].components(separatedBy: " ").filter { !$0.isEmpty } : []

                let commit = GitCommit(
                    repository: repo,
                    sha: sha,
                    shortSHA: shortSHA,
                    date: Date(timeIntervalSince1970: timestamp),
                    subject: subject,
                    author: author,
                    authorEmail: authorEmail,
                    committer: committer,
                    committerEmail: committerEmail,
                    message: subject,
                    parentSHAs: parentSHAs
                )

                commits.append(commit)
            }

            projectCommits = commits
        } catch {}
    }

    @objc public func cleanup() {
        projectCommits.removeAll()
    }
}

@objc public class GitRepositoryWatcher: NSObject {
    @objc public weak var repository: GitRepository?

    @objc public init(repository: GitRepository) {
        self.repository = repository
        super.init()
        // FSEvents implementation would go here
    }

    @objc public func stop() {
        // Stop watching
    }
}

@objc public class HookExecutionResult: NSObject {
    @objc public let success: Bool
    @objc public let output: String?

    @objc public init(success: Bool, output: String?) {
        self.success = success
        self.output = output
        super.init()
    }
}

