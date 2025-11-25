//
//  GitRef.swift
//  GitX
//
//  Swift conversion of PBGitRef
//  Original by Pieter de Bie on 06-09-08
//

import Foundation

public enum GitRefType: String {
    case tag = "tag"
    case branch = "branch"
    case remote = "remote"
    case remoteBranch = "remote branch"
}

public struct GitRefPrefix {
    public static let tag = "refs/tags/"
    public static let branch = "refs/heads/"
    public static let remote = "refs/remotes/"
}

@objc public class GitRef: NSObject, GitRefish {

    @objc public let ref: String

    @objc public init(string: String) {
        self.ref = string
        super.init()
    }

    @objc public class func ref(from string: String) -> GitRef {
        return GitRef(string: string)
    }

    // MARK: - Type Detection

    @objc public var isBranch: Bool {
        return ref.hasPrefix(GitRefPrefix.branch)
    }

    @objc public var isTag: Bool {
        return ref.hasPrefix(GitRefPrefix.tag)
    }

    @objc public var isRemote: Bool {
        return ref.hasPrefix(GitRefPrefix.remote)
    }

    @objc public var isRemoteBranch: Bool {
        guard isRemote else { return false }
        return ref.components(separatedBy: "/").count > 3
    }

    // MARK: - Name Extraction

    @objc public var type: String? {
        if isBranch { return "head" }
        if isTag { return "tag" }
        if isRemote { return "remote" }
        return nil
    }

    @objc public var tagName: String? {
        guard isTag else { return nil }
        return shortName
    }

    @objc public var branchName: String? {
        guard isBranch else { return nil }
        return shortName
    }

    @objc public var remoteName: String? {
        guard isRemote else { return nil }
        let components = ref.components(separatedBy: "/")
        guard components.count > 2 else { return nil }
        return components[2]
    }

    @objc public var remoteBranchName: String? {
        guard isRemoteBranch, let remote = remoteName else { return nil }
        let shortName = self.shortName
        let startIndex = shortName.index(shortName.startIndex, offsetBy: remote.count + 1)
        return String(shortName[startIndex...])
    }

    @objc public func isEqual(to otherRef: GitRef) -> Bool {
        return ref == otherRef.ref
    }

    @objc public var remoteRef: GitRef? {
        guard isRemote, let remoteName = remoteName else { return nil }
        return GitRef(string: GitRefPrefix.remote + remoteName)
    }

    // MARK: - GitRefish Protocol

    @objc public var refishName: String {
        return ref
    }

    @objc public var shortName: String {
        guard let type = type else { return ref }
        let prefixLength = type.count + 7 // "refs/" + type + "/"
        guard ref.count > prefixLength else { return ref }
        return String(ref.dropFirst(prefixLength))
    }

    @objc public var refishType: String {
        if isBranch { return GitRefType.branch.rawValue }
        if isTag { return GitRefType.tag.rawValue }
        if isRemoteBranch { return GitRefType.remoteBranch.rawValue }
        if isRemote { return GitRefType.remote.rawValue }
        return ""
    }

    // MARK: - Equatable & Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? GitRef else { return false }
        return ref == other.ref
    }

    public override var hash: Int {
        return ref.hashValue
    }

    public override var description: String {
        return shortName
    }
}
