//
//  HistoryView.swift
//  GitX
//
//  Commit history view with table and detail pane
//

import SwiftUI
import HighlightSwift

struct HistoryView: View {
    @ObservedObject var document: RepositoryDocument
    @Binding var selectedCommit: CommitInfo?
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var graphLayouts: [String: CommitGraphLayout] = [:]

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case local = "Local"
    }

    var filteredCommits: [CommitInfo] {
        var commits = document.state.commits

        if !searchText.isEmpty {
            commits = commits.filter { commit in
                commit.summary.localizedCaseInsensitiveContains(searchText) ||
                commit.author.localizedCaseInsensitiveContains(searchText) ||
                commit.shortOID.localizedCaseInsensitiveContains(searchText)
            }
        }

        return commits
    }

    var body: some View {
        PersistentVSplitView(
            autosaveName: "HistoryViewSplit",
            topMinHeight: 150,
            bottomMinHeight: 150
        ) {
            // Top: Commit list
            VStack(spacing: 0) {
                // Filter bar
                filterBar

                // Commit table
                commitTable
            }
        } bottom: {
            // Bottom: Commit detail
            if let commit = selectedCommit {
                CommitDetailView(commit: commit, document: document)
            } else {
                emptyDetailView
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filterMode) {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Branch dropdown
            Menu {
                Button("All branches") {
                    document.loadCommits(fromBranch: nil)
                }
                Divider()
                ForEach(document.state.branches, id: \.self) { branch in
                    Button(branch) {
                        document.loadCommits(fromBranch: branch)
                    }
                }
            } label: {
                HStack {
                    Text(document.state.selectedBranch ?? "All branches")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 200)

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Subject, Author, SHA", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Commit Table

    private var commitTable: some View {
        CommitTableView(
            commits: filteredCommits,
            graphLayouts: graphLayouts,
            commitRefs: document.state.commitRefs,
            selectedCommit: $selectedCommit
        )
        .onAppear {
            computeGraphLayouts()
        }
        .onChange(of: document.state.commits) { _, _ in
            computeGraphLayouts()
        }
    }

    private func computeGraphLayouts() {
        // Compute on background thread
        let commits = document.state.commits
        DispatchQueue.global(qos: .userInitiated).async {
            let layouts = CommitGraphComputer.computeLayout(for: commits)
            DispatchQueue.main.async {
                graphLayouts = layouts
            }
        }
    }

    // MARK: - Empty Detail View

    private var emptyDetailView: some View {
        VStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Select a commit to view details")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

}

// MARK: - Commit Detail View

struct CommitDetailView: View {
    let commit: CommitInfo
    @ObservedObject var document: RepositoryDocument
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            commitHeader

            Divider()

            // Content tabs
            TabView(selection: $selectedTab) {
                // Diff view
                DiffContentView(commit: commit, document: document)
                    .tabItem { Text("Changes") }
                    .tag(0)

                // File tree
                FileTreeView(commit: commit, document: document)
                    .tabItem { Text("Files") }
                    .tag(1)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var commitHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subject
            Text(commit.summary)
                .font(.headline)

            HStack(spacing: 20) {
                // Author
                HStack(spacing: 4) {
                    Text("Author:")
                        .foregroundColor(.secondary)
                    Text("\(commit.author) <\(commit.authorEmail)>")
                }

                // Date
                HStack(spacing: 4) {
                    Text("Date:")
                        .foregroundColor(.secondary)
                    Text(commit.date, format: .dateTime)
                }
            }
            .font(.caption)

            HStack(spacing: 20) {
                // SHA
                HStack(spacing: 4) {
                    Text("SHA:")
                        .foregroundColor(.secondary)
                    Text(commit.oid)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                // Parent
                if let parent = commit.parents.first {
                    HStack(spacing: 4) {
                        Text("Parent:")
                            .foregroundColor(.secondary)
                        Text(String(parent.prefix(7)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
            }
            .font(.caption)

            // Full message if different from summary
            if commit.message != commit.summary {
                Text(commit.message)
                    .font(.body)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}

// MARK: - Diff Content View

struct DiffContentView: View {
    let commit: CommitInfo
    @ObservedObject var document: RepositoryDocument
    @State private var diffResult: DiffResult?
    @State private var selectedFile: FileChange?
    @State private var isLoading = true

    var body: some View {
        PersistentHSplitView(
            autosaveName: "DiffContentViewSplit",
            leadingMinWidth: 180,
            trailingMinWidth: 300
        ) {
            // File list
            fileListView
        } trailing: {
            // Diff detail
            diffDetailView
        }
        .onAppear {
            loadDiff()
        }
        .onChange(of: commit.oid) { _, _ in
            loadDiff()
        }
    }

    private var fileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Changed Files")
                    .font(.headline)
                Spacer()
                if let diff = diffResult {
                    Text("\(diff.files.count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff = diffResult {
                List(diff.files, selection: $selectedFile) { file in
                    DiffFileRow(file: file)
                        .tag(file)
                }
                .listStyle(.plain)
            } else {
                Text("No changes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var diffDetailView: some View {
        Group {
            if let file = selectedFile {
                FileDiffView(file: file)
            } else if let diff = diffResult, let firstFile = diff.files.first {
                FileDiffView(file: firstFile)
                    .onAppear {
                        selectedFile = firstFile
                    }
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a file to view changes")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadDiff() {
        isLoading = true
        selectedFile = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = document.getDiff(for: commit)

            DispatchQueue.main.async {
                diffResult = result
                isLoading = false
                if let firstFile = result?.files.first {
                    selectedFile = firstFile
                }
            }
        }
    }
}

// MARK: - Diff File Row

struct DiffFileRow: View {
    let file: FileChange

    var body: some View {
        HStack(spacing: 8) {
            // Change type indicator
            Text(file.changeType.symbol)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(file.changeType.color)
                .frame(width: 16)

            // File icon
            Image(systemName: fileIcon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            // File name
            VStack(alignment: .leading, spacing: 2) {
                Text(file.path.components(separatedBy: "/").last ?? file.path)
                    .lineLimit(1)

                if file.path.contains("/") {
                    Text(file.path.components(separatedBy: "/").dropLast().joined(separator: "/"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Binary indicator
            if file.isBinary {
                Text("binary")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
    }

    private var fileIcon: String {
        let ext = (file.path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm", "h": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml": return "doc.text"
        case "md", "txt": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}

// MARK: - File Diff View

struct FileDiffView: View {
    let file: FileChange

    private var languageHint: String? {
        let ext = (file.path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack {
                Image(systemName: "doc.text")
                Text(file.displayPath)
                    .font(.headline)
                Spacer()
                Text(file.changeType.symbol)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(file.changeType.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if file.isBinary {
                VStack {
                    Image(systemName: "doc.zipper")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Binary file")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if file.hunks.isEmpty {
                VStack {
                    Image(systemName: "doc")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No content changes")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(file.hunks) { hunk in
                                HunkView(hunk: hunk, languageHint: languageHint)
                            }
                        }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

// MARK: - Hunk View

struct HunkView: View {
    let hunk: DiffHunk
    let languageHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))

            // Lines
            ForEach(hunk.lines) { line in
                DiffLineView(line: line, languageHint: languageHint)
            }
        }
    }
}

// MARK: - Diff Line View

struct DiffLineView: View {
    let line: DiffLine
    let languageHint: String?

    @State private var highlightedContent: AttributedString?
    @Environment(\.colorScheme) private var colorScheme

    private static let highlighter = Highlight()

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 0) {
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
                Text(line.newLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.trailing, 8)

            // Prefix (+, -, space)
            Text(line.type.prefix)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.type.textColor)
                .frame(width: 16)

            // Content with syntax highlighting
            if let highlighted = highlightedContent {
                Text(highlighted)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(line.content.trimmingCharacters(in: .newlines))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(line.type == .context ? .primary : line.type.textColor)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(line.type.backgroundColor)
        .task(id: line.content) {
            await highlightContent()
        }
    }

    private func highlightContent() async {
        let content = line.content.trimmingCharacters(in: .newlines)
        guard !content.isEmpty else { return }

        // Preserve leading whitespace (HighlightSwift trims it)
        let leadingWhitespace = String(content.prefix(while: { $0.isWhitespace }))
        let trimmedContent = String(content.dropFirst(leadingWhitespace.count))

        guard !trimmedContent.isEmpty else {
            // Line is only whitespace
            highlightedContent = AttributedString(content)
            return
        }

        let colors: HighlightColors = colorScheme == .dark ? .dark(.xcode) : .light(.xcode)

        do {
            var highlighted: AttributedString
            if let hint = languageHint {
                highlighted = try await Self.highlighter.attributedText(
                    trimmedContent,
                    language: hint,
                    colors: colors
                )
            } else {
                highlighted = try await Self.highlighter.attributedText(
                    trimmedContent,
                    colors: colors
                )
            }

            // Restore leading whitespace
            if !leadingWhitespace.isEmpty {
                highlightedContent = AttributedString(leadingWhitespace) + highlighted
            } else {
                highlightedContent = highlighted
            }
        } catch {
            // Fall back to plain text on error
            highlightedContent = nil
        }
    }
}

// MARK: - File Tree View

struct FileTreeView: View {
    let commit: CommitInfo
    @ObservedObject var document: RepositoryDocument
    @State private var diffResult: DiffResult?
    @State private var expandedPaths: Set<String> = []
    @State private var selectedFile: FileChange?

    var body: some View {
        PersistentHSplitView(
            autosaveName: "FileTreeViewSplit",
            leadingMinWidth: 200,
            trailingMinWidth: 300
        ) {
            // Tree view
            treeView
        } trailing: {
            // File content
            fileContentView
        }
        .onAppear {
            loadDiff()
        }
        .onChange(of: commit.oid) { _, _ in
            loadDiff()
        }
    }

    private var treeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let diff = diffResult {
                List {
                    ForEach(buildTree(from: diff.files), id: \.path) { node in
                        TreeNodeView(
                            node: node,
                            expandedPaths: $expandedPaths,
                            selectedFile: $selectedFile
                        )
                    }
                }
                .listStyle(.sidebar)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileContentView: some View {
        Group {
            if let file = selectedFile {
                FileDiffView(file: file)
            } else {
                VStack {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a file to view changes")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadDiff() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = document.getDiff(for: commit)
            DispatchQueue.main.async {
                diffResult = result
            }
        }
    }

    private func buildTree(from files: [FileChange]) -> [TreeNode] {
        var root: [String: TreeNode] = [:]

        for file in files {
            let components = file.path.components(separatedBy: "/")
            var currentPath = ""

            for (index, component) in components.enumerated() {
                let isLast = index == components.count - 1
                let parentPath = currentPath
                currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"

                if root[currentPath] == nil {
                    root[currentPath] = TreeNode(
                        name: component,
                        path: currentPath,
                        isDirectory: !isLast,
                        file: isLast ? file : nil,
                        children: []
                    )
                }

                if !parentPath.isEmpty, var parent = root[parentPath] {
                    if !parent.children.contains(where: { $0.path == currentPath }) {
                        parent.children.append(root[currentPath]!)
                        root[parentPath] = parent
                    }
                }
            }
        }

        // Return top-level nodes
        return root.values
            .filter { !$0.path.contains("/") }
            .sorted { $0.isDirectory && !$1.isDirectory || ($0.isDirectory == $1.isDirectory && $0.name < $1.name) }
    }
}

// MARK: - Tree Node

struct TreeNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let file: FileChange?
    var children: [TreeNode]
}

struct TreeNodeView: View {
    let node: TreeNode
    @Binding var expandedPaths: Set<String>
    @Binding var selectedFile: FileChange?

    var isExpanded: Bool {
        expandedPaths.contains(node.path)
    }

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { newValue in
                        if newValue {
                            expandedPaths.insert(node.path)
                        } else {
                            expandedPaths.remove(node.path)
                        }
                    }
                )
            ) {
                ForEach(node.children.sorted {
                    $0.isDirectory && !$1.isDirectory || ($0.isDirectory == $1.isDirectory && $0.name < $1.name)
                }) { child in
                    TreeNodeView(
                        node: child,
                        expandedPaths: $expandedPaths,
                        selectedFile: $selectedFile
                    )
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else if let file = node.file {
            Button(action: { selectedFile = file }) {
                HStack {
                    Text(file.changeType.symbol)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(file.changeType.color)
                    Label(node.name, systemImage: "doc")
                }
            }
            .buttonStyle(.plain)
            .background(selectedFile?.path == file.path ? Color.accentColor.opacity(0.2) : Color.clear)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView(
        document: RepositoryDocument(),
        selectedCommit: .constant(nil)
    )
    .frame(width: 800, height: 600)
}
