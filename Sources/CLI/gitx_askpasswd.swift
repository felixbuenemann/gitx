//
//  gitx_askpasswd.swift
//  GitX
//
//  SSH password prompt helper for GitX
//  Swift conversion of gitx_askpasswd_main.m
//

import AppKit

class PasswordPanelDelegate: NSObject, NSApplicationDelegate {
    var passwordPanel: NSPanel?
    var passwordField: NSSecureTextField?

    func createPanel() -> NSPanel {
        if let existing = passwordPanel {
            return existing
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 134),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.title = "GitX SSH Remote Login"
        panel.center()

        let contentView = panel.contentView!

        // OK Button
        let okButton = NSButton(frame: NSRect(x: 280, y: 20, width: 100, height: 24))
        okButton.title = "OK"
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.target = self
        okButton.action = #selector(doOKButton(_:))
        contentView.addSubview(okButton)

        // Cancel Button
        let cancelButton = NSButton(frame: NSRect(x: 174, y: 20, width: 100, height: 24))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(doCancelButton(_:))
        contentView.addSubview(cancelButton)

        // Password Field
        let passField = NSSecureTextField(frame: NSRect(x: 104, y: 68, width: 276, height: 22))
        passField.isEditable = true
        passField.isSelectable = true
        passField.isBezeled = true
        passField.bezelStyle = .squareBezel
        contentView.addSubview(passField)
        passwordField = passField

        // Password Label
        let passLabel = NSTextField(frame: NSRect(x: 100, y: 98, width: 280, height: 16))
        passLabel.stringValue = "Please enter your password:"
        passLabel.isEditable = false
        passLabel.isSelectable = false
        passLabel.isBordered = false
        passLabel.drawsBackground = false
        contentView.addSubview(passLabel)

        // GitX Icon
        let iconView = NSImageView(frame: NSRect(x: 20, y: 56, width: 64, height: 64))
        if let bundlePath = Bundle.main.bundlePath as NSString?,
           let icon = NSImage(contentsOfFile: bundlePath.appendingPathComponent("gitx.icns")) {
            iconView.image = icon
        } else if let appIcon = NSImage(named: NSImage.applicationIconName) {
            iconView.image = appIcon
        }
        contentView.addSubview(iconView)

        passwordPanel = panel
        return panel
    }

    @objc func doOKButton(_ sender: Any?) {
        if let password = passwordField?.stringValue {
            print(password)
        }
        NSApplication.shared.stopModal(withCode: .OK)
    }

    @objc func doCancelButton(_ sender: Any?) {
        NSApplication.shared.stopModal(withCode: .cancel)
    }
}

// MARK: - Main Entry Point

// Close stderr to stop Cocoa log messages from being picked up by GitX
close(STDERR_FILENO)

// Transform to foreground app
var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))

let app = NSApplication.shared
let delegate = PasswordPanelDelegate()
app.delegate = delegate

let panel = delegate.createPanel()

app.activate(ignoringOtherApps: true)
panel.makeKeyAndOrderFront(nil)
delegate.passwordField?.selectText(nil)

let response = app.runModal(for: panel)

exit(response == .OK ? 0 : 1)
