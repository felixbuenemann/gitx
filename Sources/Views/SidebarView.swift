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
    var onSubmoduleSelected: ((SubmoduleInfo) -> Void)?

    // Per-window expansion state
    @State private var branchesExpanded = true
    @State private var remotesExpanded = true
    @State private var tagsExpanded = true
    @State private var stashesExpanded = true
    @State private var submodulesExpanded = true
    @State private var otherExpanded = true

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

            // Stashes
            Section(isExpanded: $stashesExpanded) {
                if state.stashes.isEmpty {
                    Text("No stashes")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(state.stashes) { stash in
                        HStack {
                            Image(systemName: "tray.full")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stash.message.isEmpty ? "stash@{\(stash.id)}" : stash.message)
                                    .lineLimit(1)
                                Text(stash.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(SidebarItem.stash(stash.id))
                    }
                }
            } header: {
                Label("STASHES", systemImage: "tray.2")
            }

            // Submodules
            Section(isExpanded: $submodulesExpanded) {
                if state.submodules.isEmpty {
                    Text("No submodules")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(state.submodules) { submodule in
                        Button {
                            if submodule.isCheckedOut {
                                onSubmoduleSelected?(submodule)
                            }
                        } label: {
                            HStack {
                                Image(systemName: submodule.isCheckedOut ? "folder.fill" : "folder")
                                    .foregroundColor(submodule.isCheckedOut ? .accentColor : .secondary)
                                Text(submodule.name)
                                    .foregroundColor(submodule.isCheckedOut ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!submodule.isCheckedOut)
                    }
                }
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
