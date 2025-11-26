//
//  CommitView.swift
//  GitX
//
//  View for staging and committing changes
//

import SwiftUI

struct CommitView: View {
    @ObservedObject var document: RepositoryDocument
    @State private var commitMessage = ""
    @State private var stagedFiles: [FileChange] = []
    @State private var unstagedFiles: [FileChange] = []
    @State private var selectedFile: FileChange?

    var body: some View {
        PersistentHSplitView(
            autosaveName: "CommitViewSplit",
            leadingMinWidth: 220,
            trailingMinWidth: 300
        ) {
            // Left: File lists
            VStack(spacing: 0) {
                // Staged files
                stagedFilesSection

                Divider()

                // Unstaged files
                unstagedFilesSection

                Divider()

                // Commit area
                commitSection
            }
        } trailing: {
            // Right: Diff view
            diffView
        }
        .onAppear {
            loadChanges()
        }
    }

    // MARK: - Staged Files

    private var stagedFilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Staged Changes")
                    .font(.headline)
                Spacer()
                Text("\(stagedFiles.count)")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List(stagedFiles, selection: $selectedFile) { file in
                StagingFileRow(file: file) {
                    unstageFile(file)
                }
            }
        }
    }

    // MARK: - Unstaged Files

    private var unstagedFilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unstaged Changes")
                    .font(.headline)
                Spacer()
                Text("\(unstagedFiles.count)")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List(unstagedFiles, selection: $selectedFile) { file in
                StagingFileRow(file: file) {
                    stageFile(file)
                }
            }
        }
    }

    // MARK: - Commit Section

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit Message")
                .font(.headline)

            TextEditor(text: $commitMessage)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color.gray.opacity(0.3))

            HStack {
                Spacer()

                Button("Commit") {
                    performCommit()
                }
                .disabled(commitMessage.isEmpty || stagedFiles.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
    }

    // MARK: - Diff View

    private var diffView: some View {
        Group {
            if let file = selectedFile {
                FileDiffView(file: file)
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
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Actions

    private func loadChanges() {
        // TODO: Load actual working directory changes from repository
        // For now, show placeholder
    }

    private func stageFile(_ file: FileChange) {
        if let index = unstagedFiles.firstIndex(of: file) {
            unstagedFiles.remove(at: index)
            stagedFiles.append(file)
        }
    }

    private func unstageFile(_ file: FileChange) {
        if let index = stagedFiles.firstIndex(of: file) {
            stagedFiles.remove(at: index)
            unstagedFiles.append(file)
        }
    }

    private func performCommit() {
        guard !commitMessage.isEmpty, !stagedFiles.isEmpty else { return }

        // TODO: Perform actual commit via SwiftGitX
        print("Committing: \(commitMessage)")

        // Clear state
        commitMessage = ""
        stagedFiles.removeAll()
        loadChanges()
    }
}

// MARK: - Staging File Row

struct StagingFileRow: View {
    let file: FileChange
    let action: () -> Void

    var body: some View {
        HStack {
            Text(file.changeType.symbol)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(file.changeType.color)
                .frame(width: 16)

            Text(file.path)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    CommitView(document: RepositoryDocument())
        .frame(width: 800, height: 600)
}
