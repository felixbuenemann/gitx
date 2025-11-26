//
//  CommitTableView.swift
//  GitX
//
//  NSTableView wrapper for commit list with graph visualization
//

import SwiftUI
import AppKit

// MARK: - Commit Table View

struct CommitTableView: NSViewRepresentable {
    let commits: [CommitInfo]
    let graphLayouts: [String: CommitGraphLayout]
    let commitRefs: [String: [RefInfo]]
    @Binding var selectedCommit: CommitInfo?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        // SHA column
        let shaColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sha"))
        shaColumn.title = "SHA"
        shaColumn.width = 70
        shaColumn.minWidth = 60
        shaColumn.maxWidth = 100
        tableView.addTableColumn(shaColumn)

        // Graph column
        let graphColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("graph"))
        graphColumn.title = "Graph"
        graphColumn.width = 100
        graphColumn.minWidth = 30
        graphColumn.maxWidth = 300
        tableView.addTableColumn(graphColumn)

        // Subject column
        let subjectColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("subject"))
        subjectColumn.title = "Subject"
        subjectColumn.width = 400
        subjectColumn.minWidth = 200
        tableView.addTableColumn(subjectColumn)

        // Author column
        let authorColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("author"))
        authorColumn.title = "Author"
        authorColumn.width = 120
        authorColumn.minWidth = 80
        authorColumn.maxWidth = 200
        tableView.addTableColumn(authorColumn)

        // Date column
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date"
        dateColumn.width = 100
        dateColumn.minWidth = 80
        dateColumn.maxWidth = 150
        tableView.addTableColumn(dateColumn)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.commits = commits
        context.coordinator.graphLayouts = graphLayouts
        context.coordinator.commitRefs = commitRefs
        context.coordinator.selectedCommitBinding = $selectedCommit

        if let tableView = scrollView.documentView as? NSTableView {
            tableView.reloadData()

            // Update selection
            if let selected = selectedCommit,
               let index = commits.firstIndex(where: { $0.oid == selected.oid }) {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(commits: commits, graphLayouts: graphLayouts, commitRefs: commitRefs, selectedCommit: $selectedCommit)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var commits: [CommitInfo]
        var graphLayouts: [String: CommitGraphLayout]
        var commitRefs: [String: [RefInfo]]
        var selectedCommitBinding: Binding<CommitInfo?>
        weak var tableView: NSTableView?

        private let dateFormatter: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter
        }()

        init(commits: [CommitInfo], graphLayouts: [String: CommitGraphLayout], commitRefs: [String: [RefInfo]], selectedCommit: Binding<CommitInfo?>) {
            self.commits = commits
            self.graphLayouts = graphLayouts
            self.commitRefs = commitRefs
            self.selectedCommitBinding = selectedCommit
            super.init()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return commits.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < commits.count else { return nil }
            let commit = commits[row]

            switch tableColumn?.identifier.rawValue {
            case "sha":
                let textField = NSTextField(labelWithString: commit.shortOID)
                textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                textField.textColor = .systemOrange
                return textField

            case "graph":
                let layout = graphLayouts[commit.oid]
                let view = GraphCellView(layout: layout, row: row, totalRows: commits.count)
                return view

            case "subject":
                let stackView = NSStackView()
                stackView.orientation = .horizontal
                stackView.spacing = 4
                stackView.alignment = .centerY

                // Add ref badges
                let refs = commitRefs[commit.oid] ?? []
                for ref in refs {
                    let badge = createRefBadge(ref: ref)
                    stackView.addArrangedSubview(badge)
                }

                // Add subject text
                let textField = NSTextField(labelWithString: commit.summary)
                textField.lineBreakMode = .byTruncatingTail
                textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stackView.addArrangedSubview(textField)

                return stackView

            case "author":
                let textField = NSTextField(labelWithString: commit.author)
                textField.lineBreakMode = .byTruncatingTail
                return textField

            case "date":
                let relativeDate = dateFormatter.localizedString(for: commit.date, relativeTo: Date())
                let textField = NSTextField(labelWithString: relativeDate)
                return textField

            default:
                return nil
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < commits.count {
                selectedCommitBinding.wrappedValue = commits[selectedRow]
            } else {
                selectedCommitBinding.wrappedValue = nil
            }
        }

        private func createRefBadge(ref: RefInfo) -> NSView {
            let label = NSTextField(labelWithString: ref.name)
            label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            label.alignment = .center

            let (bgColor, textColor) = refColors(for: ref)
            label.textColor = textColor
            label.backgroundColor = bgColor
            label.drawsBackground = true
            label.isBordered = false
            label.wantsLayer = true
            label.layer?.cornerRadius = 3

            // Add padding by using a container view
            let container = NSView()
            container.wantsLayer = true
            container.layer?.cornerRadius = 3
            container.layer?.backgroundColor = bgColor.cgColor

            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
            ])

            container.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            return container
        }

        private func refColors(for ref: RefInfo) -> (NSColor, NSColor) {
            switch ref.type {
            case .remoteBranch:
                return (.systemPurple, .white)
            case .tag:
                return (.systemYellow, .black)
            case .localBranch:
                return (.systemGreen, .black)
            }
        }
    }
}

// MARK: - Graph Cell View

class GraphCellView: NSView {
    let layout: CommitGraphLayout?
    let row: Int
    let totalRows: Int

    private let columnWidth: CGFloat = 10
    private let nodeRadius: CGFloat = 4

    // Colors matching original GitX (hue-based)
    static let laneColors: [NSColor] = {
        let count = 8
        var colors: [NSColor] = []
        for i in 0..<count {
            let hue = CGFloat(i) / CGFloat(count)
            colors.append(NSColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0))
        }
        return colors
    }()

    init(layout: CommitGraphLayout?, row: Int, totalRows: Int) {
        self.layout = layout
        self.row = row
        self.totalRows = totalRows
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let layout = layout else {
            // Draw simple dot if no layout
            NSColor.systemBlue.setFill()
            let dotRect = NSRect(x: 5, y: bounds.midY - 4, width: 8, height: 8)
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        let centerY = bounds.midY

        // Draw all lines
        for line in layout.lines {
            let color = Self.laneColors[line.colorIndex % Self.laneColors.count]
            color.setStroke()

            let fromX = columnX(line.from)
            let toX = columnX(line.to)

            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .square

            if line.upper {
                // Draw from top of cell to center
                path.move(to: NSPoint(x: fromX, y: bounds.maxY))
                path.line(to: NSPoint(x: toX, y: centerY))
            } else {
                // Draw from center to bottom of cell
                path.move(to: NSPoint(x: fromX, y: centerY))
                path.line(to: NSPoint(x: toX, y: bounds.minY))
            }

            path.stroke()
        }

        // Draw commit node
        let nodeX = columnX(layout.position)

        // Black outline
        NSColor.black.setFill()
        let outerRect = NSRect(
            x: nodeX - nodeRadius,
            y: centerY - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )
        NSBezierPath(ovalIn: outerRect).fill()

        // Inner fill (white, or orange for first commit which is HEAD)
        let innerRadius = nodeRadius - 1.2
        let innerRect = NSRect(
            x: nodeX - innerRadius,
            y: centerY - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )

        let fillColor: NSColor = (row == 0)
            ? NSColor(red: 0xfc/255.0, green: 0xa6/255.0, blue: 0x4f/255.0, alpha: 1.0)
            : .white
        fillColor.setFill()
        NSBezierPath(ovalIn: innerRect).fill()
    }

    private func columnX(_ column: Int) -> CGFloat {
        return CGFloat(column) * columnWidth + 5
    }
}
