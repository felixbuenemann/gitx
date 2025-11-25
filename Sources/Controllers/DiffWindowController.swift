//
//  DiffWindowController.swift
//  GitX
//
//  Diff window controller
//

import AppKit

@objc public class DiffWindowController: NSWindowController {

    // MARK: - Properties

    private var diffView: DiffView!
    private var diffText: String

    // MARK: - Initialization

    @objc public init(diff: String) {
        self.diffText = diff
        super.init(window: nil)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        window.title = "Diff"
        window.center()

        diffView = DiffView(frame: window.contentView!.bounds)
        diffView.autoresizingMask = [.width, .height]
        diffView.diffText = diffText

        window.contentView?.addSubview(diffView)
        self.window = window
    }
}
