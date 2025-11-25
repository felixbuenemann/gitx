//
//  GitDefaults.swift
//  GitX
//
//  Swift conversion of PBGitDefaults
//  Original by Jeff Mesnil on 19/10/08
//

import Foundation

public enum GitDefaults {

    // MARK: - Keys

    private enum Keys {
        static let commitMessageViewVerticalLineLength = "PBCommitMessageViewVerticalLineLength"
        static let commitMessageViewVerticalBodyLineLength = "PBCommitMessageViewVerticalBodyLineLength"
        static let commitMessageViewHasVerticalLine = "PBCommitMessageViewHasVerticalLine"
        static let enableGist = "PBEnableGist"
        static let enableGravatar = "PBEnableGravatar"
        static let confirmPublicGists = "PBConfirmPublicGists"
        static let publicGist = "PBGistPublic"
        static let showWhitespaceDifferences = "PBShowWhitespaceDifferences"
        static let openCurDirOnLaunch = "PBOpenCurDirOnLaunch"
        static let showOpenPanelOnLaunch = "PBShowOpenPanelOnLaunch"
        static let shouldCheckoutBranch = "PBShouldCheckoutBranch"
        static let recentCloneDestination = "PBRecentCloneDestination"
        static let showStageView = "PBShowStageView"
        static let openPreviousDocumentsOnLaunch = "PBOpenPreviousDocumentsOnLaunch"
        static let previousDocumentPaths = "PBPreviousDocumentPaths"
        static let branchFilterState = "PBBranchFilter"
        static let historySearchMode = "PBHistorySearchMode"
        static let suppressedDialogWarnings = "Suppressed Dialog Warnings"
        static let useRepositoryWatcher = "PBUseRepositoryWatcher"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let verticalLineLength = 50
        static let verticalBodyLineLength = 72
    }

    // MARK: - Registration

    public static func registerDefaults() {
        let defaults: [String: Any] = [
            Keys.commitMessageViewVerticalLineLength: Defaults.verticalLineLength,
            Keys.commitMessageViewVerticalBodyLineLength: Defaults.verticalBodyLineLength,
            Keys.commitMessageViewHasVerticalLine: true,
            Keys.enableGist: true,
            Keys.enableGravatar: true,
            Keys.confirmPublicGists: true,
            Keys.publicGist: false,
            Keys.showWhitespaceDifferences: true,
            Keys.openCurDirOnLaunch: true,
            Keys.showOpenPanelOnLaunch: true,
            Keys.shouldCheckoutBranch: true,
            Keys.openPreviousDocumentsOnLaunch: false,
            Keys.historySearchMode: HistorySearchMode.basic.rawValue,
            Keys.useRepositoryWatcher: true
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    // MARK: - Commit Message View

    public static var commitMessageViewVerticalLineLength: Int {
        return UserDefaults.standard.integer(forKey: Keys.commitMessageViewVerticalLineLength)
    }

    public static var commitMessageViewVerticalBodyLineLength: Int {
        return UserDefaults.standard.integer(forKey: Keys.commitMessageViewVerticalBodyLineLength)
    }

    public static var commitMessageViewHasVerticalLine: Bool {
        return UserDefaults.standard.bool(forKey: Keys.commitMessageViewHasVerticalLine)
    }

    // MARK: - Gist & Gravatar

    public static var isGistEnabled: Bool {
        return UserDefaults.standard.bool(forKey: Keys.enableGist)
    }

    public static var isGravatarEnabled: Bool {
        return UserDefaults.standard.bool(forKey: Keys.enableGravatar)
    }

    public static var confirmPublicGists: Bool {
        return UserDefaults.standard.bool(forKey: Keys.confirmPublicGists)
    }

    public static var isGistPublic: Bool {
        return UserDefaults.standard.bool(forKey: Keys.publicGist)
    }

    // MARK: - Display Options

    public static var showWhitespaceDifferences: Bool {
        return UserDefaults.standard.bool(forKey: Keys.showWhitespaceDifferences)
    }

    public static var shouldCheckoutBranch: Bool {
        get { return UserDefaults.standard.bool(forKey: Keys.shouldCheckoutBranch) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.shouldCheckoutBranch) }
    }

    public static var recentCloneDestination: String? {
        get { return UserDefaults.standard.string(forKey: Keys.recentCloneDestination) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.recentCloneDestination) }
    }

    public static var showStageView: Bool {
        get { return UserDefaults.standard.bool(forKey: Keys.showStageView) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.showStageView) }
    }

    // MARK: - Branch Filter

    public static var branchFilter: Int {
        get { return UserDefaults.standard.integer(forKey: Keys.branchFilterState) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.branchFilterState) }
    }

    // MARK: - History Search

    public enum HistorySearchMode: Int {
        case basic = 0
        case pickaxe = 1
        case regex = 2
        case path = 3
    }

    public static var historySearchMode: HistorySearchMode {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: Keys.historySearchMode)
            return HistorySearchMode(rawValue: rawValue) ?? .basic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.historySearchMode)
        }
    }

    // MARK: - Repository Watcher

    public static var useRepositoryWatcher: Bool {
        return UserDefaults.standard.bool(forKey: Keys.useRepositoryWatcher)
    }

    // MARK: - Suppressed Dialogs

    public static func suppressDialogWarning(for dialog: String) {
        var warnings = suppressedDialogWarnings
        warnings.insert(dialog)
        UserDefaults.standard.set(Array(warnings), forKey: Keys.suppressedDialogWarnings)
    }

    public static func isDialogWarningSuppressed(for dialog: String) -> Bool {
        return suppressedDialogWarnings.contains(dialog)
    }

    public static func resetAllDialogWarnings() {
        UserDefaults.standard.set(nil, forKey: Keys.suppressedDialogWarnings)
        UserDefaults.standard.synchronize()
    }

    private static var suppressedDialogWarnings: Set<String> {
        let array = UserDefaults.standard.array(forKey: Keys.suppressedDialogWarnings) as? [String] ?? []
        return Set(array)
    }
}
