//
//  GitXApp.swift
//  GitX
//
//  SwiftUI App entry point
//

import SwiftUI
import SwiftGitX

@main
struct GitXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState.shared)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository...") {
                    AppState.shared.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Clone Repository...") {
                    AppState.shared.showCloneSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()
            }

            // Repository menu
            CommandMenu("Repository") {
                Button("Refresh") {
                    AppState.shared.document?.refreshState()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Reveal in Finder") {
                    if let url = AppState.shared.document?.state.url {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }

                Button("Open in Terminal") {
                    if let url = AppState.shared.document?.state.url {
                        AppState.shared.openInTerminal(url)
                    }
                }
            }

            // View menu additions
            CommandGroup(after: .toolbar) {
                Divider()

                Button("History") {
                    AppState.shared.selectedView = .history
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Commit") {
                    AppState.shared.selectedView = .commit
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.document != nil {
                RepositoryView(document: appState.document!)
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $appState.showCloneSheet) {
            CloneRepositorySheet()
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var recentRepositories: [URL] = []

    var body: some View {
        HStack(spacing: 0) {
            // Left side - branding and actions
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)

                VStack(spacing: 8) {
                    Text("GitX")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("A gitk clone for macOS")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    Button(action: { appState.showOpenPanel() }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Open Repository...")
                        }
                        .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: { appState.showCloneSheet = true }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Clone Repository...")
                        }
                        .frame(width: 200)
                    }
                    .controlSize(.large)
                }

                Spacer()
            }
            .frame(width: 300)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Right side - recent repositories
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Repositories")
                    .font(.headline)
                    .padding()

                if recentRepositories.isEmpty {
                    VStack {
                        Spacer()
                        Text("No recent repositories")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(recentRepositories, id: \.self) { url in
                        Button(action: { appState.openRepository(at: url) }) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(url.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 300)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadRecentRepositories()
        }
    }

    private func loadRecentRepositories() {
        // Load from UserDefaults
        if let paths = UserDefaults.standard.stringArray(forKey: "recentRepositories") {
            recentRepositories = paths.compactMap { URL(fileURLWithPath: $0) }
        }
    }
}

// MARK: - Clone Repository Sheet

struct CloneRepositorySheet: View {
    @EnvironmentObject var appState: AppState
    @State private var remoteURL = ""
    @State private var localPath = ""
    @State private var isCloning = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Clone Repository")
                .font(.headline)

            Form {
                TextField("Remote URL:", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    TextField("Local Path:", text: $localPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectDirectory()
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    appState.showCloneSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Clone") {
                    // TODO: Implement cloning
                    appState.showCloneSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(remoteURL.isEmpty || localPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var document: RepositoryDocument?
    @Published var showCloneSheet = false
    @Published var selectedView: ViewMode = .history

    enum ViewMode {
        case history
        case commit
    }

    init() {
        // Initialize SwiftGitX
        try? SwiftGitX.initialize()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            openRepository(at: url)
        }
    }

    func openRepository(at url: URL) {
        let doc = RepositoryDocument()
        do {
            try doc.loadRepository(at: url)
            self.document = doc
            addToRecentRepositories(url)
        } catch {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Failed to open repository"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func addToRecentRepositories(_ url: URL) {
        var recent = UserDefaults.standard.stringArray(forKey: "recentRepositories") ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        if recent.count > 10 {
            recent = Array(recent.prefix(10))
        }
        UserDefaults.standard.set(recent, forKey: "recentRepositories")
    }

    func openInTerminal(_ url: URL) {
        let terminalApp = UserDefaults.standard.string(forKey: "terminalApp") ?? "Terminal"
        let script: String

        switch terminalApp {
        case "iTerm":
            script = """
                tell application "iTerm"
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(url.path)'"
                    end tell
                end tell
            """
        default:
            script = """
                tell application "Terminal"
                    do script "cd '\(url.path)'"
                    activate
                end tell
            """
        }

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshRepository = Notification.Name("refreshRepository")
    static let revealInFinder = Notification.Name("revealInFinder")
    static let openInTerminal = Notification.Name("openInTerminal")
    static let showHistoryView = Notification.Name("showHistoryView")
    static let showCommitView = Notification.Name("showCommitView")
    static let showCloneSheet = Notification.Name("showCloneSheet")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "gitBinaryPath": "/usr/bin/git",
            "terminalApp": "Terminal"
        ])
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Shutdown SwiftGitX
        try? SwiftGitX.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Handle opening files/folders from Finder or command line
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                AppState.shared.openRepository(at: url)
            }
        }
    }
}
