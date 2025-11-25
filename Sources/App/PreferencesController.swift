//
//  PreferencesController.swift
//  GitX
//
//  Preferences window controller
//

import AppKit

@objc public class PreferencesController: NSWindowController {

    // MARK: - Outlets

    @IBOutlet private weak var gitPathField: NSTextField?
    @IBOutlet private weak var verticalLineLengthField: NSTextField?
    @IBOutlet private weak var showVerticalLineCheckbox: NSButton?
    @IBOutlet private weak var enableGistCheckbox: NSButton?
    @IBOutlet private weak var enableGravatarCheckbox: NSButton?
    @IBOutlet private weak var showWhitespaceCheckbox: NSButton?

    // MARK: - Initialization

    public override init(window: NSWindow?) {
        super.init(window: nil)
        Bundle.main.loadNibNamed("Preferences", owner: self, topLevelObjects: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func windowDidLoad() {
        super.windowDidLoad()
        loadPreferences()
    }

    // MARK: - Loading/Saving

    private func loadPreferences() {
        gitPathField?.stringValue = GitBinary.path ?? ""
        verticalLineLengthField?.integerValue = GitDefaults.commitMessageViewVerticalLineLength
        showVerticalLineCheckbox?.state = GitDefaults.commitMessageViewHasVerticalLine ? .on : .off
        enableGistCheckbox?.state = GitDefaults.isGistEnabled ? .on : .off
        enableGravatarCheckbox?.state = GitDefaults.isGravatarEnabled ? .on : .off
        showWhitespaceCheckbox?.state = GitDefaults.showWhitespaceDifferences ? .on : .off
    }

    // MARK: - Actions

    @IBAction func chooseGitPath(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the git binary"

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "gitExecutable")
            gitPathField?.stringValue = url.path
        }
    }

    @IBAction func resetDialogWarnings(_ sender: Any?) {
        GitDefaults.resetAllDialogWarnings()

        let alert = NSAlert()
        alert.messageText = "Dialog Warnings Reset"
        alert.informativeText = "All dialog warnings have been reset and will be shown again."
        alert.runModal()
    }
}
