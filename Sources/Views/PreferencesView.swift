//
//  PreferencesView.swift
//  GitX
//
//  Settings/Preferences window
//

import SwiftUI

struct PreferencesView: View {
    @AppStorage("gitBinaryPath") private var gitPath = "/usr/bin/git"
    @AppStorage("terminalApp") private var terminalApp = "Terminal"
    @AppStorage("diffTool") private var diffTool = ""
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("refreshInterval") private var refreshInterval = 30.0

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            gitTab
                .tabItem {
                    Label("Git", systemImage: "arrow.triangle.branch")
                }

            advancedTab
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Terminal") {
                Picker("Application:", selection: $terminalApp) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                    Text("Warp").tag("Warp")
                }
            }

            Section("Display") {
                Toggle("Show hidden files", isOn: $showHiddenFiles)
            }

            Section("Updates") {
                HStack {
                    Text("Auto-refresh interval:")
                    Slider(value: $refreshInterval, in: 10...120, step: 10) {
                        Text("Refresh")
                    }
                    Text("\(Int(refreshInterval))s")
                        .frame(width: 40)
                }
            }
        }
        .padding()
    }

    // MARK: - Git Tab

    private var gitTab: some View {
        Form {
            Section("Git Binary") {
                HStack {
                    TextField("Path:", text: $gitPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        chooseGitPath()
                    }
                }

                Text("Current: \(gitPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Diff Tool") {
                TextField("External diff tool:", text: $diffTool)
                    .textFieldStyle(.roundedBorder)

                Text("Leave empty to use built-in diff viewer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section("Performance") {
                Text("Advanced settings will appear here")
                    .foregroundColor(.secondary)
            }

            Section("Reset") {
                Button("Reset All Settings") {
                    resetSettings()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func chooseGitPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select Git binary"

        if panel.runModal() == .OK, let url = panel.url {
            gitPath = url.path
        }
    }

    private func resetSettings() {
        gitPath = "/usr/bin/git"
        terminalApp = "Terminal"
        diffTool = ""
        showHiddenFiles = false
        refreshInterval = 30.0
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}
