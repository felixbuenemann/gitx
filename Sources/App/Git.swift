//
//  Git.swift
//  GitX
//
//  Swift wrapper for libgit2 providing a clean API for Git operations.
//

import Foundation
import libgit2

// MARK: - Git Initialization

enum Git {
    private static var initialized = false

    static func initialize() {
        guard !initialized else { return }
        git_libgit2_init()
        initialized = true
    }

    static func shutdown() {
        git_libgit2_shutdown()
        initialized = false
    }
}

// MARK: - Git Error

struct GitError: Error, LocalizedError {
    let code: Int32
    let message: String

    init(code: Int32, message: String? = nil) {
        self.code = code
        if let message = message {
            self.message = message
        } else if let error = git_error_last() {
            self.message = String(cString: error.pointee.message)
        } else {
            self.message = "Unknown git error (code: \(code))"
        }
    }

    var errorDescription: String? { message }

    static func check(_ status: Int32, message: String? = nil) throws {
        guard status == GIT_OK.rawValue else {
            throw GitError(code: status, message: message)
        }
    }
}

// MARK: - Repository

final class GitRepository {
    let pointer: OpaquePointer

    init(at url: URL) throws {
        var pointer: OpaquePointer?
        let status = git_repository_open(&pointer, url.path)
        try GitError.check(status, message: "Failed to open repository at \(url.path)")
        self.pointer = pointer!
    }

    deinit {
        git_repository_free(pointer)
    }

    var path: URL {
        URL(fileURLWithPath: String(cString: git_repository_path(pointer)))
    }

    var workdir: URL? {
        guard let path = git_repository_workdir(pointer) else { return nil }
        return URL(fileURLWithPath: String(cString: path))
    }

    // MARK: - HEAD

    func head() throws -> GitReference {
        var ref: OpaquePointer?
        let status = git_repository_head(&ref, pointer)
        try GitError.check(status, message: "Failed to get HEAD")
        return GitReference(pointer: ref!)
    }

    // MARK: - Branches

    func localBranches() throws -> [GitBranch] {
        var branches: [GitBranch] = []
        var iterator: OpaquePointer?

        let status = git_branch_iterator_new(&iterator, pointer, GIT_BRANCH_LOCAL)
        try GitError.check(status)
        defer { git_branch_iterator_free(iterator) }

        var ref: OpaquePointer?
        var type = GIT_BRANCH_LOCAL

        while git_branch_next(&ref, &type, iterator) == GIT_OK.rawValue {
            if let branch = GitBranch(pointer: ref!, type: type) {
                branches.append(branch)
            }
        }

        return branches
    }

    func remoteBranches() throws -> [GitBranch] {
        var branches: [GitBranch] = []
        var iterator: OpaquePointer?

        let status = git_branch_iterator_new(&iterator, pointer, GIT_BRANCH_REMOTE)
        try GitError.check(status)
        defer { git_branch_iterator_free(iterator) }

        var ref: OpaquePointer?
        var type = GIT_BRANCH_REMOTE

        while git_branch_next(&ref, &type, iterator) == GIT_OK.rawValue {
            if let branch = GitBranch(pointer: ref!, type: type) {
                branches.append(branch)
            }
        }

        return branches
    }

    // MARK: - Tags

    func tags() throws -> [GitTag] {
        var tags: [GitTag] = []

        var callback: git_tag_foreach_cb = { name, oid, payload in
            guard let name = name, let oid = oid else { return 0 }
            let tags = payload!.assumingMemoryBound(to: [(String, git_oid)].self)
            tags.pointee.append((String(cString: name), oid.pointee))
            return 0
        }

        var tagData: [(String, git_oid)] = []
        let status = withUnsafeMutablePointer(to: &tagData) { ptr in
            git_tag_foreach(pointer, callback, ptr)
        }
        try GitError.check(status)

        for (name, oid) in tagData {
            // Resolve to commit
            var commit: OpaquePointer?
            var commitOid = oid

            // Try to peel to commit (handles annotated tags)
            var obj: OpaquePointer?
            if git_object_lookup(&obj, pointer, &commitOid, GIT_OBJECT_ANY) == GIT_OK.rawValue {
                var peeled: OpaquePointer?
                if git_object_peel(&peeled, obj, GIT_OBJECT_COMMIT) == GIT_OK.rawValue {
                    commitOid = git_object_id(peeled)!.pointee
                    git_object_free(peeled)
                }
                git_object_free(obj)
            }

            let shortName = name.hasPrefix("refs/tags/") ? String(name.dropFirst(10)) : name
            tags.append(GitTag(name: shortName, oid: GitOID(raw: commitOid)))
        }

        return tags
    }

    // MARK: - Remotes

    func remotes() throws -> [String] {
        var strarray = git_strarray()
        let status = git_remote_list(&strarray, pointer)
        try GitError.check(status)
        defer { git_strarray_dispose(&strarray) }

        var names: [String] = []
        for i in 0..<strarray.count {
            if let str = strarray.strings[i] {
                names.append(String(cString: str))
            }
        }
        return names
    }

    // MARK: - Stashes

    func stashes() throws -> [GitStashEntry] {
        var entries: [GitStashEntry] = []

        var callback: git_stash_cb = { index, message, oid, payload in
            guard let oid = oid else { return 0 }
            let entries = payload!.assumingMemoryBound(to: [GitStashEntry].self)
            let msg = message.map { String(cString: $0) } ?? ""
            entries.pointee.append(GitStashEntry(
                index: index,
                message: msg,
                oid: GitOID(raw: oid.pointee)
            ))
            return 0
        }

        let status = withUnsafeMutablePointer(to: &entries) { ptr in
            git_stash_foreach(pointer, callback, ptr)
        }
        try GitError.check(status)

        return entries
    }

    // MARK: - Log (Commit Walking)

    func log(from oid: GitOID? = nil, limit: Int = 1000) throws -> [GitCommit] {
        var walker: OpaquePointer?
        var status = git_revwalk_new(&walker, pointer)
        try GitError.check(status)
        defer { git_revwalk_free(walker) }

        git_revwalk_sorting(walker, GIT_SORT_TIME.rawValue)

        if var startOid = oid?.raw {
            status = git_revwalk_push(walker, &startOid)
        } else {
            status = git_revwalk_push_head(walker)
        }
        try GitError.check(status)

        var commits: [GitCommit] = []
        var commitOid = git_oid()

        while git_revwalk_next(&commitOid, walker) == GIT_OK.rawValue && commits.count < limit {
            if let commit = try? lookupCommit(oid: GitOID(raw: commitOid)) {
                commits.append(commit)
            }
        }

        return commits
    }

    // MARK: - Lookups

    func lookupCommit(oid: GitOID) throws -> GitCommit {
        var commit: OpaquePointer?
        var rawOid = oid.raw
        let status = git_commit_lookup(&commit, pointer, &rawOid)
        try GitError.check(status, message: "Failed to lookup commit \(oid.hex)")
        return GitCommit(pointer: commit!)
    }

    func lookupBlob(oid: GitOID) throws -> Data {
        var blob: OpaquePointer?
        var rawOid = oid.raw
        let status = git_blob_lookup(&blob, pointer, &rawOid)
        try GitError.check(status, message: "Failed to lookup blob \(oid.hex)")
        defer { git_blob_free(blob) }

        let size = git_blob_rawsize(blob)
        guard let content = git_blob_rawcontent(blob) else {
            return Data()
        }
        return Data(bytes: content, count: Int(size))
    }

    func lookupTree(oid: GitOID) throws -> GitTree {
        var tree: OpaquePointer?
        var rawOid = oid.raw
        let status = git_tree_lookup(&tree, pointer, &rawOid)
        try GitError.check(status, message: "Failed to lookup tree \(oid.hex)")
        return GitTree(pointer: tree!)
    }

    // MARK: - Diff

    func diff(commit: GitCommit) throws -> GitDiff {
        let tree = try commit.tree(in: self)

        var parentTree: GitTree? = nil
        if commit.parentCount > 0, let parentOid = commit.parentOID(at: 0) {
            let parent = try lookupCommit(oid: parentOid)
            parentTree = try parent.tree(in: self)
        }

        var diffPointer: OpaquePointer?
        let status = git_diff_tree_to_tree(
            &diffPointer,
            pointer,
            parentTree?.pointer,
            tree.pointer,
            nil
        )
        try GitError.check(status, message: "Failed to create diff")

        return GitDiff(pointer: diffPointer!)
    }
}

// MARK: - OID

struct GitOID: Hashable {
    var raw: git_oid

    init(raw: git_oid) {
        self.raw = raw
    }

    init?(hex: String) {
        var oid = git_oid()
        guard git_oid_fromstr(&oid, hex) == GIT_OK.rawValue else {
            return nil
        }
        self.raw = oid
    }

    var hex: String {
        var buffer = [CChar](repeating: 0, count: Int(GIT_OID_MAX_HEXSIZE) + 1)
        var oid = raw
        git_oid_tostr(&buffer, buffer.count, &oid)
        return String(cString: buffer)
    }

    var abbreviated: String {
        String(hex.prefix(7))
    }

    static func == (lhs: GitOID, rhs: GitOID) -> Bool {
        var l = lhs.raw
        var r = rhs.raw
        return git_oid_equal(&l, &r) != 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hex)
    }
}

// MARK: - Reference

struct GitReference {
    let pointer: OpaquePointer

    var name: String {
        guard let name = git_reference_name(pointer) else { return "" }
        return String(cString: name)
    }

    var shortName: String {
        guard let name = git_reference_shorthand(pointer) else { return "" }
        return String(cString: name)
    }

    var targetOID: GitOID? {
        guard let oid = git_reference_target(pointer) else { return nil }
        return GitOID(raw: oid.pointee)
    }

    var isBranch: Bool {
        git_reference_is_branch(pointer) != 0
    }

    var isRemote: Bool {
        git_reference_is_remote(pointer) != 0
    }

    var isTag: Bool {
        git_reference_is_tag(pointer) != 0
    }
}

// MARK: - Branch

struct GitBranch {
    let name: String
    let targetOID: GitOID
    let isRemote: Bool

    init?(pointer: OpaquePointer, type: git_branch_t) {
        var namePtr: UnsafePointer<CChar>?
        guard git_branch_name(&namePtr, pointer) == GIT_OK.rawValue,
              let name = namePtr else {
            git_reference_free(pointer)
            return nil
        }

        self.name = String(cString: name)
        self.isRemote = type == GIT_BRANCH_REMOTE

        // Get target OID - need to resolve for symbolic refs
        var resolved: OpaquePointer?
        if git_reference_resolve(&resolved, pointer) == GIT_OK.rawValue,
           let oid = git_reference_target(resolved) {
            self.targetOID = GitOID(raw: oid.pointee)
            git_reference_free(resolved)
        } else if let oid = git_reference_target(pointer) {
            self.targetOID = GitOID(raw: oid.pointee)
        } else {
            git_reference_free(pointer)
            return nil
        }

        git_reference_free(pointer)
    }
}

// MARK: - Tag

struct GitTag {
    let name: String
    let oid: GitOID
}

// MARK: - Stash Entry

struct GitStashEntry {
    let index: Int
    let message: String
    let oid: GitOID
}

// MARK: - Commit

struct GitCommit {
    let pointer: OpaquePointer

    var oid: GitOID {
        GitOID(raw: git_commit_id(pointer)!.pointee)
    }

    var message: String {
        guard let msg = git_commit_message(pointer) else { return "" }
        return String(cString: msg).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var summary: String {
        guard let summary = git_commit_summary(pointer) else { return "" }
        return String(cString: summary)
    }

    var author: GitSignature {
        GitSignature(raw: git_commit_author(pointer)!.pointee)
    }

    var committer: GitSignature {
        GitSignature(raw: git_commit_committer(pointer)!.pointee)
    }

    var parentCount: Int {
        Int(git_commit_parentcount(pointer))
    }

    func parentOID(at index: Int) -> GitOID? {
        guard let oid = git_commit_parent_id(pointer, UInt32(index)) else { return nil }
        return GitOID(raw: oid.pointee)
    }

    func tree(in repo: GitRepository) throws -> GitTree {
        var tree: OpaquePointer?
        let status = git_commit_tree(&tree, pointer)
        try GitError.check(status)
        return GitTree(pointer: tree!)
    }
}

// MARK: - Signature

struct GitSignature {
    let name: String
    let email: String
    let date: Date

    init(raw: git_signature) {
        self.name = String(cString: raw.name)
        self.email = String(cString: raw.email)
        self.date = Date(timeIntervalSince1970: TimeInterval(raw.when.time))
    }
}

// MARK: - Tree

final class GitTree {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        git_tree_free(pointer)
    }

    var oid: GitOID {
        GitOID(raw: git_tree_id(pointer)!.pointee)
    }

    var entryCount: Int {
        git_tree_entrycount(pointer)
    }

    func entry(at index: Int) -> GitTreeEntry? {
        guard let entry = git_tree_entry_byindex(pointer, index) else { return nil }
        return GitTreeEntry(entry: entry)
    }

    func entry(named name: String) -> GitTreeEntry? {
        guard let entry = git_tree_entry_byname(pointer, name) else { return nil }
        return GitTreeEntry(entry: entry)
    }
}

// MARK: - Tree Entry

struct GitTreeEntry {
    private let entry: OpaquePointer

    init(entry: OpaquePointer) {
        self.entry = entry
    }

    var name: String {
        guard let name = git_tree_entry_name(entry) else { return "" }
        return String(cString: name)
    }

    var oid: GitOID {
        GitOID(raw: git_tree_entry_id(entry)!.pointee)
    }

    var type: git_object_t {
        git_tree_entry_type(entry)
    }

    var isBlob: Bool {
        type == GIT_OBJECT_BLOB
    }

    var isTree: Bool {
        type == GIT_OBJECT_TREE
    }
}

// MARK: - Diff

final class GitDiff {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        git_diff_free(pointer)
    }

    var deltaCount: Int {
        git_diff_num_deltas(pointer)
    }

    func delta(at index: Int) -> GitDiffDelta? {
        guard let delta = git_diff_get_delta(pointer, index) else { return nil }
        return GitDiffDelta(raw: delta.pointee, index: index)
    }

    /// Get patch for a specific file (lazy loading)
    func patch(at index: Int) -> GitPatch? {
        var patchPointer: OpaquePointer?
        let status = git_patch_from_diff(&patchPointer, pointer, index)
        guard status == GIT_OK.rawValue, let ptr = patchPointer else { return nil }
        return GitPatch(pointer: ptr)
    }
}

// MARK: - Diff Delta

struct GitDiffDelta {
    let index: Int
    let status: git_delta_t
    let oldFile: GitDiffFile
    let newFile: GitDiffFile
    let isBinary: Bool

    var path: String {
        newFile.path.isEmpty ? oldFile.path : newFile.path
    }

    init(raw: git_diff_delta, index: Int) {
        self.index = index
        self.status = raw.status
        self.oldFile = GitDiffFile(raw: raw.old_file)
        self.newFile = GitDiffFile(raw: raw.new_file)
        self.isBinary = (raw.flags & GIT_DIFF_FLAG_BINARY.rawValue) != 0
    }
}

// MARK: - Diff File

struct GitDiffFile {
    let path: String
    let oid: GitOID
    let size: Int

    init(raw: git_diff_file) {
        self.path = String(cString: raw.path)
        self.oid = GitOID(raw: raw.id)
        self.size = Int(raw.size)
    }
}

// MARK: - Patch

final class GitPatch {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        git_patch_free(pointer)
    }

    var hunkCount: Int {
        git_patch_num_hunks(pointer)
    }

    func hunk(at index: Int) -> GitHunk? {
        var hunkPointer: UnsafePointer<git_diff_hunk>?
        var lineCount: Int = 0

        let status = git_patch_get_hunk(&hunkPointer, &lineCount, pointer, index)
        guard status == GIT_OK.rawValue, let hunk = hunkPointer?.pointee else {
            return nil
        }

        var lines: [GitDiffLine] = []
        for lineIndex in 0..<lineCount {
            var linePointer: UnsafePointer<git_diff_line>?
            if git_patch_get_line_in_hunk(&linePointer, pointer, index, lineIndex) == GIT_OK.rawValue,
               let line = linePointer?.pointee {
                lines.append(GitDiffLine(raw: line))
            }
        }

        return GitHunk(raw: hunk, lines: lines)
    }
}

// MARK: - Hunk

struct GitHunk {
    let header: String
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [GitDiffLine]

    init(raw: git_diff_hunk, lines: [GitDiffLine]) {
        self.header = withUnsafePointer(to: raw.header) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 128) { charPtr in
                String(cString: charPtr)
            }
        }
        self.oldStart = Int(raw.old_start)
        self.oldLines = Int(raw.old_lines)
        self.newStart = Int(raw.new_start)
        self.newLines = Int(raw.new_lines)
        self.lines = lines
    }
}

// MARK: - Diff Line

struct GitDiffLine {
    let origin: Int8
    let content: String
    let oldLineNo: Int?
    let newLineNo: Int?

    var isAddition: Bool { origin == 43 }  // '+'
    var isDeletion: Bool { origin == 45 }  // '-'
    var isContext: Bool { origin == 32 }   // ' '

    init(raw: git_diff_line) {
        self.origin = raw.origin

        if let contentPtr = raw.content, raw.content_len > 0 {
            // Create string from pointer and length
            let data = Data(bytes: contentPtr, count: raw.content_len)
            self.content = String(data: data, encoding: .utf8) ?? ""
        } else {
            self.content = ""
        }

        self.oldLineNo = raw.old_lineno > 0 ? Int(raw.old_lineno) : nil
        self.newLineNo = raw.new_lineno > 0 ? Int(raw.new_lineno) : nil
    }
}
