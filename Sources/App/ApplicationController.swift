//
//  ApplicationController.swift
//  GitX
//
//  Swift conversion of ApplicationController
//

import AppKit

@objc public class ApplicationController: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var clonePanel: CloneRepositoryPanel?
    private var preferencesController: PreferencesController?

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults
        GitDefaults.registerDefaults()

        // Check for git binary
        if GitBinary.path == nil {
            showGitNotFoundAlert()
        }

        // Handle URL schemes
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return showOpenPanel()
    }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        return openRepository(at: url)
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            _ = openRepository(at: url)
        }
    }

    // MARK: - Menu Actions

    @IBAction func openDocument(_ sender: Any?) {
        _ = showOpenPanel()
    }

    @IBAction func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesController()
        }
        preferencesController?.showWindow(sender)
    }

    @IBAction func showClonePanel(_ sender: Any?) {
        if clonePanel == nil {
            clonePanel = CloneRepositoryPanel()
        }
        clonePanel?.showWindow(sender)
    }

    @IBAction func showAbout(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(sender)
    }

    // MARK: - Repository Operations

    @discardableResult
    private func openRepository(at url: URL) -> Bool {
        do {
            let document = try NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            )
            return document != nil
        } catch {
            showError(error)
            return false
        }
    }

    private func showOpenPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select a Git repository to open"

        let response = panel.runModal()
        if response == .OK {
            for url in panel.urls {
                _ = openRepository(at: url)
            }
            return true
        }
        return false
    }

    // MARK: - URL Handling

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        if url.scheme == "gitx" {
            // Handle gitx:// URLs
            if let host = url.host {
                switch host {
                case "clone":
                    if let repoURL = url.queryParameters["url"] {
                        cloneRepository(from: repoURL)
                    }
                case "open":
                    if let path = url.path.removingPercentEncoding {
                        _ = openRepository(at: URL(fileURLWithPath: path))
                    }
                default:
                    break
                }
            }
        }
    }

    private func cloneRepository(from urlString: String) {
        if clonePanel == nil {
            clonePanel = CloneRepositoryPanel()
        }
        clonePanel?.setRepositoryURL(urlString)
        clonePanel?.showWindow(nil)
    }

    // MARK: - Error Handling

    private func showGitNotFoundAlert() {
        let alert = NSAlert()
        alert.messageText = "Git not found"
        alert.informativeText = GitBinary.notFoundError
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

// MARK: - URL Extensions

private extension URL {
    var queryParameters: [String: String] {
        var params: [String: String] = [:]
        if let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                params[item.name] = item.value
            }
        }
        return params
    }
}
