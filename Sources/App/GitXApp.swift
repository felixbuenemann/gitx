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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window - shows welcome or repo based on pending URL
        WindowGroup("GitX", id: "main", for: URL.self) { $url in
            MainWindowView(initialURL: url)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository...") {
                    AppState.shared.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Clone Repository...") {
                    // TODO: Implement clone sheet
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()
            }

            // Repository menu
            CommandMenu("Repository") {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshRepository, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Reveal in Finder") {
                    NotificationCenter.default.post(name: .revealInFinder, object: nil)
                }

                Button("Open in Terminal") {
                    NotificationCenter.default.post(name: .openInTerminal, object: nil)
                }
            }

            // View menu additions
            CommandGroup(after: .toolbar) {
                Divider()

                Button("History") {
                    NotificationCenter.default.post(name: .showHistoryView, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Commit") {
                    NotificationCenter.default.post(name: .showCommitView, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

// MARK: - Window Frame Persistence

struct WindowFrameModifier: ViewModifier {
    let repositoryPath: String?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor(repositoryPath: repositoryPath))
    }
}

struct WindowAccessor: NSViewRepresentable {
    let repositoryPath: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.observeWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.repositoryPath = repositoryPath
        if let window = nsView.window {
            context.coordinator.observeWindow(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(repositoryPath: repositoryPath)
    }

    class Coordinator: NSObject {
        var repositoryPath: String?
        private var observedWindow: NSWindow?
        private var frameObservation: NSObjectProtocol?
        private var hasRestoredFrame = false

        init(repositoryPath: String?) {
            self.repositoryPath = repositoryPath
            super.init()
        }

        deinit {
            if let observation = frameObservation {
                NotificationCenter.default.removeObserver(observation)
            }
        }

        func observeWindow(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            // Remove old observation
            if let observation = frameObservation {
                NotificationCenter.default.removeObserver(observation)
            }

            // Restore frame if we have a repository path
            if !hasRestoredFrame, let path = repositoryPath {
                hasRestoredFrame = true
                restoreFrame(for: window, repositoryPath: path)
            }

            // Observe frame changes to save position
            frameObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveFrame()
            }

            // Also observe window move
            let moveObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveFrame()
            }

            // Store move observation (we'll just let it live with the window)
            _ = moveObservation
        }

        private func restoreFrame(for window: NSWindow, repositoryPath: String) {
            let key = "window.frame.\(repositoryPath)"
            guard let frameString = UserDefaults.standard.string(forKey: key) else { return }
            let frame = NSRectFromString(frameString)
            if frame.width > 0 && frame.height > 0 {
                // Validate frame is on a visible screen
                let screens = NSScreen.screens
                let frameOnScreen = screens.contains { screen in
                    screen.visibleFrame.intersects(frame)
                }
                if frameOnScreen {
                    window.setFrame(frame, display: true)
                }
            }
        }

        private func saveFrame() {
            guard let window = observedWindow, let path = repositoryPath else { return }
            let key = "window.frame.\(path)"
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: key)
        }
    }
}

// MARK: - Main Window View

struct MainWindowView: View {
    let initialURL: URL?
    @StateObject private var document = RepositoryDocument()
    @State private var loadError: String?
    @State private var hasLoaded = false
    @State private var showCloneSheet = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let error = loadError {
                // Error view
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to open repository")
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Open Another Repository...") {
                        showOpenPanel()
                    }
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.state.url != nil {
                // Repository view
                RepositoryView(document: document)
            } else {
                // Welcome view
                WelcomeView(onOpenRepository: { url in
                    loadRepository(at: url)
                })
            }
        }
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                if let url = initialURL {
                    // We have an initial URL from WindowGroup
                    loadRepository(at: url)
                } else if let pendingURL = AppDelegate.pendingURLs.first {
                    // Claim a pending URL
                    AppDelegate.pendingURLs.removeFirst()
                    loadRepository(at: pendingURL)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRepositoryInWindow)) { notification in
            guard let url = notification.object as? URL else { return }

            if document.state.url == nil {
                // This window has no repo - load it here
                // Remove from pending if present
                AppDelegate.pendingURLs.removeAll { $0 == url }
                loadRepository(at: url)
            }
            // Windows with repos don't respond - opening new windows is handled directly
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneRepositorySheet(isPresented: $showCloneSheet)
        }
        .modifier(WindowFrameModifier(repositoryPath: document.state.url?.path))
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            loadRepository(at: url)
        }
    }

    private func loadRepository(at url: URL) {
        do {
            try document.loadRepository(at: url)
            loadError = nil
            AppState.shared.addToRecentRepositories(url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var onOpenRepository: ((URL) -> Void)?
    @State private var recentRepositories: [URL] = []
    @State private var showCloneSheet = false

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
                    Button(action: { showOpenPanel() }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Open Repository...")
                        }
                        .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: { showCloneSheet = true }) {
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
                        Button(action: { onOpenRepository?(url) }) {
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
        .sheet(isPresented: $showCloneSheet) {
            CloneRepositorySheet(isPresented: $showCloneSheet)
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            onOpenRepository?(url)
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
    @Binding var isPresented: Bool
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
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Clone") {
                    // TODO: Implement cloning
                    isPresented = false
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
        // Post notification to open in new window
        NotificationCenter.default.post(name: .openRepositoryInWindow, object: url)
    }

    func addToRecentRepositories(_ url: URL) {
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
    static let openRepositoryInWindow = Notification.Name("openRepositoryInWindow")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs that should be opened in new windows (set before app finishes launching)
    static var pendingURLs: [URL] = []
    /// Flag to indicate URLs were received before launch finished
    static var hasReceivedURLs = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "gitBinaryPath": "/usr/bin/git",
            "terminalApp": "Terminal"
        ])

        // If we received URLs during launch, post notifications after a delay
        // to ensure windows are ready
        if Self.hasReceivedURLs {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for url in Self.pendingURLs {
                    NotificationCenter.default.post(name: .openRepositoryInWindow, object: url)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Shutdown SwiftGitX
        try? SwiftGitX.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Handle opening files/folders from Finder or command line
    // This is called BEFORE applicationDidFinishLaunching when opening via URL
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.hasReceivedURLs = true
        Self.pendingURLs.append(contentsOf: urls)

        // If app is already running, post notification immediately
        if NSApp.isRunning {
            for url in urls {
                NotificationCenter.default.post(name: .openRepositoryInWindow, object: url)
            }
        }
    }
}
