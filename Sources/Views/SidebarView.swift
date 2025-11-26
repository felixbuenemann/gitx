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

    // Persist expansion state
    @AppStorage("sidebar.branchesExpanded") private var branchesExpanded = true
    @AppStorage("sidebar.remotesExpanded") private var remotesExpanded = true
    @AppStorage("sidebar.tagsExpanded") private var tagsExpanded = true
    @AppStorage("sidebar.stashesExpanded") private var stashesExpanded = true
    @AppStorage("sidebar.submodulesExpanded") private var submodulesExpanded = true
    @AppStorage("sidebar.otherExpanded") private var otherExpanded = true

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
            Section(isExpanded: $branchesExpanded) {
                ForEach(state.branches, id: \.self) { branch in
                    HStack {
                        Image(systemName: branch == state.currentBranch ? "checkmark.circle.fill" : "arrow.triangle.branch")
                            .foregroundColor(branch == state.currentBranch ? .green : .secondary)
                        Text(branch)
                            .fontWeight(branch == state.currentBranch ? .semibold : .regular)
                    }
                    .tag(SidebarItem.branch(branch))
                }
            } header: {
                Label("BRANCHES", systemImage: "arrow.triangle.branch")
            }

            // Remotes
            if !state.remotes.isEmpty {
                Section(isExpanded: $remotesExpanded) {
                    ForEach(state.remotes, id: \.self) { remote in
                        Label(remote, systemImage: "network")
                            .tag(SidebarItem.remote(remote))
                    }
                } header: {
                    Label("REMOTES", systemImage: "network")
                }
            }

            // Tags
            if !state.tags.isEmpty {
                Section(isExpanded: $tagsExpanded) {
                    ForEach(state.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarItem.tag(tag))
                    }
                } header: {
                    Label("TAGS", systemImage: "tag")
                }
            }

            // Stashes (placeholder)
            Section(isExpanded: $stashesExpanded) {
                Text("No stashes")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } header: {
                Label("STASHES", systemImage: "tray.2")
            }

            // Submodules (placeholder)
            Section(isExpanded: $submodulesExpanded) {
                Text("No submodules")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } header: {
                Label("SUBMODULES", systemImage: "folder.badge.gearshape")
            }

            // Other
            Section(isExpanded: $otherExpanded) {
                Label("Other", systemImage: "ellipsis.circle")
                    .tag(SidebarItem.other)
            } header: {
                Label("OTHER", systemImage: "ellipsis.circle")
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
