//
//  SidebarView.swift
//  GitX
//
//  Repository sidebar with branches, remotes, tags, etc.
//

import SwiftUI

struct SidebarView: View {
    let state: RepositoryState
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            // Repository header
            Section {
                Label(state.name.isEmpty ? "Repository" : state.name.uppercased(), systemImage: "folder.fill")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Stage
            Label("Stage", systemImage: "tray.and.arrow.up")
                .tag(SidebarItem.stage)

            // Branches
            Section("BRANCHES") {
                ForEach(state.branches, id: \.self) { branch in
                    HStack {
                        Image(systemName: branch == state.currentBranch ? "checkmark.circle.fill" : "arrow.triangle.branch")
                            .foregroundColor(branch == state.currentBranch ? .green : .secondary)
                        Text(branch)
                            .fontWeight(branch == state.currentBranch ? .semibold : .regular)
                    }
                    .tag(SidebarItem.branch(branch))
                }
            }

            // Remotes
            if !state.remotes.isEmpty {
                Section("REMOTES") {
                    ForEach(state.remotes, id: \.self) { remote in
                        Label(remote, systemImage: "network")
                            .tag(SidebarItem.remote(remote))
                    }
                }
            }

            // Tags
            if !state.tags.isEmpty {
                Section("TAGS") {
                    ForEach(state.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarItem.tag(tag))
                    }
                }
            }

            // Stashes (placeholder)
            Section("STASHES") {
                Text("No stashes")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Submodules (placeholder)
            Section("SUBMODULES") {
                Text("No submodules")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Other
            Section("OTHER") {
                Label("Other", systemImage: "ellipsis.circle")
                    .tag(SidebarItem.other)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        state: RepositoryState(
            name: "GitX",
            currentBranch: "main",
            branches: ["main", "develop", "feature/new-ui"],
            remotes: ["origin"],
            tags: ["v1.0", "v1.1", "v2.0"]
        ),
        selection: .constant(.history)
    )
    .frame(width: 220)
}
