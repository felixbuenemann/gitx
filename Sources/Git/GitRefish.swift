//
//  GitRefish.swift
//  GitX
//
//  Swift conversion of PBGitRefish
//  Original by Nathan Kinsinger on 12/25/09
//

import Foundation

/// Protocol for Git refs and commits that can be used in git commands
/// refishName: The full name of the ref "refs/heads/master" or the full SHA
/// shortName: A more user-friendly version of the refName, "master" or a short SHA
/// refishType: A short name for the type
@objc public protocol GitRefish {
    var refishName: String { get }
    var shortName: String { get }
    var refishType: String { get }
}
