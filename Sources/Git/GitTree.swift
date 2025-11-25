//
//  GitTree.swift
//  GitX
//
//  Swift conversion of PBGitTree
//  Original by Pieter de Bie
//

import Foundation

@objc public class GitTree: NSObject {

    @objc public weak var repository: GitRepository?
    @objc public weak var commit: GitCommit?
    @objc public weak var parent: GitTree?

    @objc public var sha: String
    @objc public var path: String
    @objc public var isLeaf: Bool

    @objc public private(set) lazy var children: [GitTree] = {
        return loadChildren()
    }()

    public init(sha: String, repository: GitRepository?, commit: GitCommit?, path: String = "", isLeaf: Bool = false) {
        self.sha = sha
        self.repository = repository
        self.commit = commit
        self.path = path
        self.isLeaf = isLeaf
        super.init()
    }

    @objc public static func root(for commit: GitCommit) -> GitTree {
        return GitTree(sha: commit.sha, repository: commit.repository, commit: commit, path: "")
    }

    private func loadChildren() -> [GitTree] {
        guard !isLeaf, let repo = repository else { return [] }

        do {
            guard let gitPath = GitBinary.path else { return [] }
            let args = ["ls-tree", sha]
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: args,
                directory: repo.workingDirectory
            )

            var trees: [GitTree] = []
            let lines = result.output.components(separatedBy: "\n")

            for line in lines where !line.isEmpty {
                // Format: mode type sha\tname
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 2 else { continue }

                let metadata = parts[0].components(separatedBy: " ")
                guard metadata.count >= 3 else { continue }

                let type = metadata[1]
                let childSha = metadata[2]
                let name = parts[1]

                let childPath = path.isEmpty ? name : "\(path)/\(name)"
                let child = GitTree(
                    sha: childSha,
                    repository: repo,
                    commit: commit,
                    path: childPath,
                    isLeaf: type == "blob"
                )
                child.parent = self
                trees.append(child)
            }

            return trees
        } catch {
            return []
        }
    }

    @objc public var fullPath: String {
        if let parent = parent, !parent.path.isEmpty {
            return "\(parent.fullPath)/\(path)"
        }
        return path
    }

    @objc public var name: String {
        return (path as NSString).lastPathComponent
    }

    @objc public var contents: String? {
        guard isLeaf, let repo = repository else { return nil }

        do {
            guard let gitPath = GitBinary.path else { return nil }
            let result = try EasyPipe.output(
                for: gitPath,
                arguments: ["show", sha],
                directory: repo.workingDirectory
            )
            return result.output
        } catch {
            return nil
        }
    }
}
