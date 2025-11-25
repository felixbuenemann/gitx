//
//  CommitHistoryView.swift
//  GitX
//
//  Commit history view
//

import AppKit

@objc public class CommitHistoryView: NSView {

    // MARK: - Properties

    @objc public weak var repository: GitRepository?
    @objc public var commits: [GitCommit] = []
    @objc public var selectedCommit: GitCommit?

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        // Create scroll view
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        // Create table view
        tableView = NSTableView(frame: bounds)
        tableView.headerView = nil
        tableView.rowHeight = 24

        // Add columns
        let graphColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("graph"))
        graphColumn.width = 100
        graphColumn.title = ""
        tableView.addTableColumn(graphColumn)

        let shaColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sha"))
        shaColumn.width = 80
        shaColumn.title = "SHA"
        tableView.addTableColumn(shaColumn)

        let subjectColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subject"))
        subjectColumn.width = 400
        subjectColumn.title = "Subject"
        tableView.addTableColumn(subjectColumn)

        let authorColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("author"))
        authorColumn.width = 150
        authorColumn.title = "Author"
        tableView.addTableColumn(authorColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.width = 150
        dateColumn.title = "Date"
        tableView.addTableColumn(dateColumn)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    // MARK: - Public Methods

    @objc public func reloadData() {
        commits = repository?.revisionList.projectCommits ?? []
        tableView.reloadData()
    }
}

// MARK: - NSTableViewDataSource

extension CommitHistoryView: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return commits.count
    }
}

// MARK: - NSTableViewDelegate

extension CommitHistoryView: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < commits.count else { return nil }
        let commit = commits[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()

        cellView.identifier = identifier

        if cellView.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.frame = cellView.bounds
            textField.autoresizingMask = [.width, .height]
            cellView.addSubview(textField)
            cellView.textField = textField
        }

        switch identifier.rawValue {
        case "sha":
            cellView.textField?.stringValue = commit.shortSHA
            cellView.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        case "subject":
            cellView.textField?.stringValue = commit.subject
        case "author":
            cellView.textField?.stringValue = commit.author
        case "date":
            cellView.textField?.stringValue = commit.dateString
        default:
            cellView.textField?.stringValue = ""
        }

        return cellView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 && row < commits.count {
            selectedCommit = commits[row]
        } else {
            selectedCommit = nil
        }
    }
}
