//
//  CloneRepositoryPanel.swift
//  GitX
//
//  Clone repository panel
//

import AppKit

@objc public class CloneRepositoryPanel: NSWindowController {

    // MARK: - Outlets

    @IBOutlet private weak var repositoryURLField: NSTextField?
    @IBOutlet private weak var destinationField: NSTextField?
    @IBOutlet private weak var cloneButton: NSButton?
    @IBOutlet private weak var progressIndicator: NSProgressIndicator?
    @IBOutlet private weak var bareCheckbox: NSButton?

    private var isCloning = false

    // MARK: - Initialization

    public override init(window: NSWindow?) {
        super.init(window: nil)
        Bundle.main.loadNibNamed("PBCloneRepositoryPanel", owner: self, topLevelObjects: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func windowDidLoad() {
        super.windowDidLoad()

        // Set default destination from preferences
        if let destination = GitDefaults.recentCloneDestination {
            destinationField?.stringValue = destination
        } else {
            destinationField?.stringValue = NSHomeDirectory()
        }
    }

    // MARK: - Public Methods

    @objc public func setRepositoryURL(_ url: String) {
        repositoryURLField?.stringValue = url
    }

    // MARK: - Actions

    @IBAction func chooseDestination(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a destination for the cloned repository"

        if panel.runModal() == .OK, let url = panel.url {
            destinationField?.stringValue = url.path
            GitDefaults.recentCloneDestination = url.path
        }
    }

    @IBAction func clone(_ sender: Any?) {
        guard !isCloning else { return }

        guard let repoURL = repositoryURLField?.stringValue, !repoURL.isEmpty else {
            showError("Please enter a repository URL")
            return
        }

        guard let destination = destinationField?.stringValue, !destination.isEmpty else {
            showError("Please choose a destination")
            return
        }

        let isBare = bareCheckbox?.state == .on

        startClone(from: repoURL, to: destination, bare: isBare)
    }

    @IBAction func cancel(_ sender: Any?) {
        window?.close()
    }

    // MARK: - Clone Operation

    private func startClone(from url: String, to destination: String, bare: Bool) {
        guard let gitPath = GitBinary.path else {
            showError("Git binary not found")
            return
        }

        isCloning = true
        cloneButton?.isEnabled = false
        progressIndicator?.startAnimation(nil)

        // Extract repository name from URL
        let repoName = (url as NSString).lastPathComponent
            .replacingOccurrences(of: ".git", with: "")
        let fullDestination = (destination as NSString).appendingPathComponent(repoName)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                var args = ["clone", "--progress"]
                if bare {
                    args.append("--bare")
                }
                args.append(url)
                args.append(fullDestination)

                let result = try EasyPipe.output(
                    for: gitPath,
                    arguments: args,
                    directory: destination
                )

                DispatchQueue.main.async {
                    self?.finishClone(success: result.exitCode == 0, destination: fullDestination, error: result.output)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishClone(success: false, destination: fullDestination, error: error.localizedDescription)
                }
            }
        }
    }

    private func finishClone(success: Bool, destination: String, error: String?) {
        isCloning = false
        cloneButton?.isEnabled = true
        progressIndicator?.stopAnimation(nil)

        if success {
            window?.close()

            // Open the cloned repository
            let url = URL(fileURLWithPath: destination)
            Task { @MainActor in
                do {
                    _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
                } catch {
                    self.showError("Failed to open cloned repository: \(error.localizedDescription)")
                }
            }
        } else {
            showError("Clone failed: \(error ?? "Unknown error")")
        }
    }

    // MARK: - Error Handling

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
