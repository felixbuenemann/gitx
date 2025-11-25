//
//  GitCommit.swift
//  GitX
//
//  Swift conversion of PBGitCommit
//  Original by Pieter de Bie on 13-06-08
//

import Foundation

public let GitCommitType = "commit"

@objc public class GitCommit: NSObject, GitRefish {

    // MARK: - Properties

    @objc public weak var repository: GitRepository?

    @objc public let sha: String
    @objc public let shortSHA: String
    @objc public let date: Date
    @objc public let subject: String
    @objc public let author: String
    @objc public let authorEmail: String
    @objc public let committer: String
    @objc public let committerEmail: String
    @objc public let message: String

    @objc public private(set) lazy var parents: [String] = {
        return _parentSHAs
    }()

    private let _parentSHAs: [String]

    @objc public var refs: [GitRef] {
        get {
            guard let repo = repository else { return [] }
            return repo.refs[sha] ?? []
        }
        set {
            repository?.refs[sha] = newValue
        }
    }

    @objc public var sign: Character = " "
    @objc public var lineInfo: GraphCellInfo?

    // MARK: - Computed Properties

    @objc public var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    @objc public lazy var tree: GitTree = {
        return GitTree.root(for: self)
    }()

    @objc public var treeContents: [GitTree] {
        return tree.children
    }

    @objc public lazy var patch: String = {
        guard let repo = repository else { return "" }
        do {
            guard let gitPath = GitBinary.path else { return "" }
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["format-patch", "-1", "--stdout", sha],
                directory: repo.workingDirectory
            )
            var patch = result.output
            if patch.hasSuffix("\n") {
                patch.removeLast()
            }
            return patch + "+GitX"
        } catch {
            return ""
        }
    }()

    @objc public var svnRevision: String? {
        guard let repo = repository, repo.hasSVNRemote else { return nil }

        let pattern = "^git-svn-id: .*@(\\d+) .*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return nil
        }

        let range = NSRange(message.startIndex..., in: message)
        if let match = regex.firstMatch(in: message, options: [], range: range) {
            if match.numberOfRanges > 1 {
                let matchRange = match.range(at: 1)
                if let swiftRange = Range(matchRange, in: message) {
                    return String(message[swiftRange])
                }
            }
        }
        return nil
    }

    // MARK: - Initialization

    public init(repository: GitRepository, sha: String, shortSHA: String, date: Date,
                subject: String, author: String, authorEmail: String,
                committer: String, committerEmail: String, message: String,
                parentSHAs: [String]) {
        self.repository = repository
        self.sha = sha
        self.shortSHA = shortSHA
        self.date = date
        self.subject = subject
        self.author = author
        self.authorEmail = authorEmail
        self.committer = committer
        self.committerEmail = committerEmail
        self.message = message
        self._parentSHAs = parentSHAs
        super.init()
    }

    // MARK: - Ref Management

    @objc public func addRef(_ ref: GitRef) {
        var currentRefs = refs
        if !currentRefs.contains(where: { $0.isEqual(to: ref) }) {
            currentRefs.append(ref)
            refs = currentRefs
        }
    }

    @objc public func removeRef(_ ref: GitRef) {
        var currentRefs = refs
        currentRefs.removeAll { $0.isEqual(to: ref) }
        refs = currentRefs
    }

    @objc public func hasRef(_ ref: GitRef) -> Bool {
        return refs.contains { $0.isEqual(to: ref) }
    }

    // MARK: - Branch Checking

    @objc public func isOnSameBranch(as other: GitCommit) -> Bool {
        guard let repo = repository else { return false }
        return repo.isOnSameBranch(sha, as: other.sha)
    }

    @objc public var isOnHeadBranch: Bool {
        guard let repo = repository, let headCommit = repo.headCommit else { return false }
        return isOnSameBranch(as: headCommit)
    }

    // MARK: - Equatable & Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? GitCommit else { return false }
        return sha == other.sha
    }

    public override var hash: Int {
        return sha.hashValue
    }

    // MARK: - GitRefish Protocol

    @objc public var refishName: String {
        return sha
    }

    @objc public var shortName: String {
        return shortSHA
    }

    @objc public var refishType: String {
        return GitCommitType
    }

    public override var description: String {
        return "\(shortSHA): \(subject)"
    }
}

// MARK: - Graph Cell Info (placeholder)

@objc public class GraphCellInfo: NSObject {
    @objc public var position: Int = 0
    @objc public var numColumns: Int = 0
}
