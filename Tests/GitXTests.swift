//
//  GitXTests.swift
//  GitXTests
//
//  Unit tests for GitX
//

import XCTest
@testable import GitXCore

final class GitXTests: XCTestCase {

    // MARK: - GitRef Tests

    func testGitRefBranchParsing() {
        let branchRef = GitRef(string: "refs/heads/main")
        XCTAssertTrue(branchRef.isBranch)
        XCTAssertFalse(branchRef.isTag)
        XCTAssertFalse(branchRef.isRemoteBranch)
        XCTAssertEqual(branchRef.shortName, "main")
    }

    func testGitRefTagParsing() {
        let tagRef = GitRef(string: "refs/tags/v1.0.0")
        XCTAssertTrue(tagRef.isTag)
        XCTAssertFalse(tagRef.isBranch)
        XCTAssertFalse(tagRef.isRemoteBranch)
        XCTAssertEqual(tagRef.shortName, "v1.0.0")
    }

    func testGitRefRemoteBranchParsing() {
        let remoteRef = GitRef(string: "refs/remotes/origin/main")
        XCTAssertTrue(remoteRef.isRemoteBranch)
        XCTAssertFalse(remoteRef.isBranch)
        XCTAssertFalse(remoteRef.isTag)
        XCTAssertEqual(remoteRef.remoteName, "origin")
        XCTAssertEqual(remoteRef.remoteBranchName, "main")
    }

    func testGitRefEquality() {
        let ref1 = GitRef(string: "refs/heads/main")
        let ref2 = GitRef(string: "refs/heads/main")
        let ref3 = GitRef(string: "refs/heads/develop")

        XCTAssertTrue(ref1.isEqual(to: ref2))
        XCTAssertFalse(ref1.isEqual(to: ref3))
    }

    // MARK: - GitRevSpecifier Tests

    func testGitRevSpecifierWithRef() {
        let ref = GitRef(string: "refs/heads/main")
        let revSpec = GitRevSpecifier(ref: ref)

        XCTAssertTrue(revSpec.isSimpleRef)
        XCTAssertNotNil(revSpec.ref)
        XCTAssertEqual(revSpec.ref?.ref, "refs/heads/main")
        XCTAssertTrue(revSpec.parameters.isEmpty)
    }

    func testGitRevSpecifierWithParameters() {
        let revSpec = GitRevSpecifier(parameters: ["HEAD~5"])

        XCTAssertFalse(revSpec.isSimpleRef)
        XCTAssertEqual(revSpec.parameters, ["HEAD~5"])
        XCTAssertNil(revSpec.ref)
    }

    func testGitRevSpecifierEquality() {
        let ref1 = GitRef(string: "refs/heads/main")
        let ref2 = GitRef(string: "refs/heads/main")
        let revSpec1 = GitRevSpecifier(ref: ref1)
        let revSpec2 = GitRevSpecifier(ref: ref2)

        XCTAssertEqual(revSpec1, revSpec2)
    }

    // MARK: - String Extensions Tests

    func testStringTruncation() {
        let longString = "This is a very long string that needs to be truncated"
        let truncated = longString.truncated(to: 20)

        XCTAssertEqual(truncated.count, 20)
        XCTAssertTrue(truncated.hasSuffix("..."))
    }

    func testStringNoTruncationNeeded() {
        let shortString = "Short"
        let result = shortString.truncated(to: 20)

        XCTAssertEqual(result, shortString)
    }

    // MARK: - GitBinary Tests

    func testGitBinaryPathExists() {
        // Git binary path should be found on most systems
        // This test may fail if git is not installed
        let path = GitBinary.path
        // We don't assert on the exact path since it varies by system
        // Just verify the function doesn't crash
        _ = path
    }

    // MARK: - GitDefaults Tests

    func testBranchFilterDefault() {
        // Test default branch filter value
        let filter = GitDefaults.branchFilter
        XCTAssertTrue(filter >= 0 && filter <= 2)
    }

    // MARK: - EasyFS Tests

    func testFileExists() {
        // Test with a file that should exist on all systems
        let exists = EasyFS.fileExists(atPath: "/")
        XCTAssertTrue(exists)
    }

    func testFileNotExists() {
        let exists = EasyFS.fileExists(atPath: "/this/path/definitely/does/not/exist/12345")
        XCTAssertFalse(exists)
    }
}
