//
//  IndexController.swift
//  GitX
//
//  Index (staging area) controller
//

import AppKit

@objc public class IndexController: NSViewController {

    // MARK: - Properties

    @objc public weak var repository: GitRepository?
    private var index: GitIndex?

    private var stagedTableView: NSTableView!
    private var unstagedTableView: NSTableView!
    private var commitMessageView: NSTextView!
    private var commitButton: NSButton!

    private var stagedFiles: [ChangedFile] = []
    private var unstagedFiles: [ChangedFile] = []

    // MARK: - View Lifecycle

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        if let repo = repository {
            index = GitIndex(repository: repo)
            setupNotifications()
            refresh()
        }
    }

    // MARK: - Setup

    private func setupViews() {
        // Create split view for staged/unstaged
        let splitView = NSSplitView(frame: view.bounds)
        splitView.isVertical = false
        splitView.autoresizingMask = [.width, .height]

        // Unstaged files section
        let unstagedContainer = createTableContainer(title: "Unstaged Changes")
        unstagedTableView = createTableView()
        unstagedTableView.dataSource = self
        unstagedTableView.delegate = self
        unstagedTableView.tag = 0
        (unstagedContainer.subviews.last as? NSScrollView)?.documentView = unstagedTableView

        // Staged files section
        let stagedContainer = createTableContainer(title: "Staged Changes")
        stagedTableView = createTableView()
        stagedTableView.dataSource = self
        stagedTableView.delegate = self
        stagedTableView.tag = 1
        (stagedContainer.subviews.last as? NSScrollView)?.documentView = stagedTableView

        splitView.addArrangedSubview(unstagedContainer)
        splitView.addArrangedSubview(stagedContainer)

        // Commit message section
        let commitContainer = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 150))

        let scrollView = NSScrollView(frame: NSRect(x: 10, y: 50, width: 580, height: 90))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        commitMessageView = NSTextView(frame: scrollView.bounds)
        commitMessageView.isRichText = false
        commitMessageView.font = NSFont.systemFont(ofSize: 13)
        scrollView.documentView = commitMessageView

        commitContainer.addSubview(scrollView)

        commitButton = NSButton(title: "Commit", target: self, action: #selector(commit(_:)))
        commitButton.frame = NSRect(x: 500, y: 10, width: 90, height: 30)
        commitButton.bezelStyle = .rounded
        commitContainer.addSubview(commitButton)

        // Add all to main view
        let mainSplit = NSSplitView(frame: view.bounds)
        mainSplit.isVertical = false
        mainSplit.autoresizingMask = [.width, .height]
        mainSplit.addArrangedSubview(splitView)
        mainSplit.addArrangedSubview(commitContainer)

        view.addSubview(mainSplit)
    }

    private func createTableContainer(title: String) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 150))

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 10, y: 125, width: 200, height: 20)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        container.addSubview(label)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)

        return container
    }

    private func createTableView() -> NSTableView {
        let tableView = NSTableView()
        tableView.headerView = nil

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.width = 580
        tableView.addTableColumn(column)

        return tableView
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexUpdated(_:)),
            name: .gitIndexUpdated,
            object: index
        )
    }

    // MARK: - Actions

    @objc public func refresh() {
        index?.refresh()
    }

    @objc private func indexUpdated(_ notification: Notification) {
        updateFileArrays()
        stagedTableView.reloadData()
        unstagedTableView.reloadData()
    }

    private func updateFileArrays() {
        guard let files = index?.indexChanges else { return }
        stagedFiles = files.filter { $0.hasStagedChanges }
        unstagedFiles = files.filter { $0.hasUnstagedChanges }
    }

    @objc func stageSelectedFiles(_ sender: Any?) {
        let selectedRows = unstagedTableView.selectedRowIndexes
        let files = selectedRows.map { unstagedFiles[$0] }
        index?.stageFiles(files)
    }

    @objc func unstageSelectedFiles(_ sender: Any?) {
        let selectedRows = stagedTableView.selectedRowIndexes
        let files = selectedRows.map { stagedFiles[$0] }
        index?.unstageFiles(files)
    }

    @objc func commit(_ sender: Any?) {
        let message = commitMessageView.string
        guard !message.isEmpty else {
            showError("Please enter a commit message")
            return
        }

        index?.commit(message: message, verify: true)
        commitMessageView.string = ""
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - NSTableViewDataSource

extension IndexController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView.tag == 0 {
            return unstagedFiles.count
        } else {
            return stagedFiles.count
        }
    }
}

// MARK: - NSTableViewDelegate

extension IndexController: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let files = tableView.tag == 0 ? unstagedFiles : stagedFiles
        guard row < files.count else { return nil }

        let file = files[row]

        let cellView = NSTableCellView()
        let textField = NSTextField(labelWithString: file.path)
        textField.frame = NSRect(x: 20, y: 0, width: 560, height: 17)

        // Status indicator
        let statusIndicator = NSTextField(labelWithString: statusSymbol(for: file.status))
        statusIndicator.frame = NSRect(x: 0, y: 0, width: 18, height: 17)
        statusIndicator.textColor = statusColor(for: file.status)

        cellView.addSubview(statusIndicator)
        cellView.addSubview(textField)
        cellView.textField = textField

        return cellView
    }

    private func statusSymbol(for status: ChangedFileStatus) -> String {
        switch status {
        case .new: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        }
    }

    private func statusColor(for status: ChangedFileStatus) -> NSColor {
        switch status {
        case .new: return .systemGreen
        case .modified: return .systemBlue
        case .deleted: return .systemRed
        }
    }
}
