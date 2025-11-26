//
//  RepositoryView.swift
//  GitX
//
//  Main repository view with sidebar and content
//

import SwiftUI

struct RepositoryView: View {
    @ObservedObject var document: RepositoryDocument
    @State private var selectedSidebarItem: SidebarItem? = .history
    @State private var selectedCommit: CommitInfo?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                state: document.state,
                selection: $selectedSidebarItem,
                onSubmoduleSelected: openSubmodule
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            contentView
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshRepository)) { _ in
            document.refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHistoryView)) { _ in
            selectedSidebarItem = .history
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommitView)) { _ in
            selectedSidebarItem = .stage
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealInFinder)) { _ in
            revealInFinder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInTerminal)) { _ in
            openInTerminal()
        }
        .onChange(of: selectedSidebarItem) { _, newValue in
            handleSidebarSelection(newValue)
        }
    }

    private func handleSidebarSelection(_ item: SidebarItem?) {
        switch item {
        case .branch(let branchName):
            document.loadCommits(fromBranch: branchName)
        case .history:
            document.loadCommits(fromBranch: nil)
        case .tag(let tagName):
            // TODO: Load commits for tag
            break
        case .remote(let remoteName):
            // TODO: Load commits for remote
            break
        case .submodule:
            // Handled via onSubmoduleSelected callback
            break
        default:
            break
        }
    }

    private func openSubmodule(_ submodule: SubmoduleInfo) {
        guard let repoURL = document.state.url, submodule.isCheckedOut else {
            return
        }

        let submoduleURL = repoURL.appendingPathComponent(submodule.path)
        // Open directly in new window - don't use notifications
        openWindow(id: "main", value: submoduleURL)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selectedSidebarItem {
        case .stage:
            CommitView(document: document)
        case .history, .branch, .remote, .tag, .stash, .submodule, .none:
            HistoryView(
                document: document,
                selectedCommit: $selectedCommit
            )
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        var title = document.state.name
        if !document.state.currentBranch.isEmpty {
            title += " (branch: \(document.state.currentBranch))"
        }
        return title
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Button(action: { selectedSidebarItem = .history }) {
            Label("History", systemImage: "clock")
        }
        .help("Show History")

        Button(action: { selectedSidebarItem = .stage }) {
            Label("Commit", systemImage: "plus.circle")
        }
        .help("Show Commit View")

        Spacer()

        Button(action: { document.refreshState() }) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Refresh Repository")
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Actions

    private func revealInFinder() {
        guard let url = document.state.url else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    private func openInTerminal() {
        guard let url = document.state.url else { return }

        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(url.path)' && clear && git status"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case stage
    case history
    case branch(String)
    case remote(String)
    case tag(String)
    case stash(Int)
    case submodule(String)
}
