//
//  RepositoryWindowController.swift
//  GitX
//
//  Main repository window controller
//

import AppKit

@objc public class RepositoryWindowController: NSWindowController {

    // MARK: - Properties

    @objc public var repository: GitRepository

    // Views
    private var splitView: NSSplitView!
    private var sidebarView: SidebarView!
    private var contentView: NSView!
    private var historyView: CommitHistoryView!
    private var diffView: DiffView!
    private var commitView: CommitViewController!

    // Controllers
    private var historyController: HistoryController!
    private var commitController: CommitController!

    private var currentMode: ViewMode = .history

    public enum ViewMode {
        case history
        case commit
    }

    // MARK: - Initialization

    @objc public init(repository: GitRepository, displayDefault: Bool) {
        self.repository = repository
        super.init(window: nil)
        setupWindow()
        if displayDefault {
            showHistoryView(nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 500)
        window.title = repository.displayName
        window.center()

        self.window = window
        setupViews()
        setupToolbar()
    }

    private func setupViews() {
        guard let window = window else { return }

        // Create main split view
        splitView = NSSplitView(frame: window.contentView!.bounds)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Create sidebar
        sidebarView = SidebarView(frame: NSRect(x: 0, y: 0, width: 200, height: 800))
        sidebarView.repository = repository

        // Create content area
        contentView = NSView(frame: NSRect(x: 200, y: 0, width: 1000, height: 800))
        contentView.autoresizingMask = [.width, .height]

        // Create history view
        historyView = CommitHistoryView(frame: contentView.bounds)
        historyView.repository = repository
        historyView.autoresizingMask = [.width, .height]

        // Create diff view
        diffView = DiffView(frame: contentView.bounds)
        diffView.autoresizingMask = [.width, .height]

        // Add views to split view
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        // Set initial divider position
        splitView.setPosition(200, ofDividerAt: 0)

        window.contentView?.addSubview(splitView)

        // Load data
        reloadData()
    }

    private func setupToolbar() {
        guard let window = window else { return }

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
    }

    // MARK: - Public Methods

    @objc public func showHistoryView(_ sender: Any?) {
        currentMode = .history
        contentView.subviews.forEach { $0.removeFromSuperview() }
        historyView.frame = contentView.bounds
        contentView.addSubview(historyView)
    }

    @objc public func showCommitView(_ sender: Any?) {
        currentMode = .commit
        // Implement commit view display
    }

    @objc public func reloadData() {
        repository.reloadRefs()
        sidebarView.reloadData()
        historyView.reloadData()
    }

    // MARK: - Modal Sheets

    @objc public func showModalSheet(_ sheet: ModalRepoSheet) {
        guard let sheetWindow = sheet.window else { return }
        window?.beginSheet(sheetWindow) { _ in }
    }

    @objc public func hideModalSheet(_ sheet: ModalRepoSheet) {
        guard let sheetWindow = sheet.window else { return }
        window?.endSheet(sheetWindow)
    }

    // MARK: - Error Display

    @objc public func showErrorSheet(title: String, message: String, output: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(message)\n\n\(output)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    @objc public func showErrorSheet(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Search

    @objc public func setHistorySearch(_ searchString: String, mode: Int) {
        // Implement search
    }
}

// MARK: - NSToolbarDelegate

extension RepositoryWindowController: NSToolbarDelegate {
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .historyItem,
            .commitItem,
            .flexibleSpace,
            .refreshItem,
            .searchItem
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .historyItem,
            .commitItem,
            .flexibleSpace,
            .searchItem
        ]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .historyItem:
            item.label = "History"
            item.paletteLabel = "History"
            item.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "History")
            item.action = #selector(showHistoryView(_:))
            item.target = self

        case .commitItem:
            item.label = "Commit"
            item.paletteLabel = "Commit"
            item.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Commit")
            item.action = #selector(showCommitView(_:))
            item.target = self

        case .refreshItem:
            item.label = "Refresh"
            item.paletteLabel = "Refresh"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.action = #selector(reloadData)
            item.target = self

        case .searchItem:
            let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
            searchField.placeholderString = "Search"
            item.view = searchField
            item.label = "Search"
            item.paletteLabel = "Search"

        default:
            return nil
        }

        return item
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let historyItem = NSToolbarItem.Identifier("history")
    static let commitItem = NSToolbarItem.Identifier("commit")
    static let refreshItem = NSToolbarItem.Identifier("refresh")
    static let searchItem = NSToolbarItem.Identifier("search")
}

// MARK: - Placeholder Controllers

@objc public class HistoryController: NSObject {
    @objc public weak var repository: GitRepository?
}

@objc public class CommitController: NSObject {
    @objc public weak var repository: GitRepository?
}

@objc public class CommitViewController: NSViewController {
    @objc public weak var repository: GitRepository?
}
