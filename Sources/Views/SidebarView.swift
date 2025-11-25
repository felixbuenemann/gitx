//
//  SidebarView.swift
//  GitX
//
//  Sidebar view for repository navigation
//

import AppKit

@objc public class SidebarView: NSView {

    // MARK: - Properties

    @objc public weak var repository: GitRepository?
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!

    private var rootItems: [SidebarItem] = []

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
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        outlineView = NSOutlineView(frame: bounds)
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 16

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = bounds.width
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.documentView = outlineView
        addSubview(scrollView)
    }

    // MARK: - Public Methods

    @objc public func reloadData() {
        buildSidebarItems()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    private func buildSidebarItems() {
        rootItems = []

        guard let repo = repository else { return }

        // Branches section
        let branchesItem = SidebarItem(title: "Branches", isGroup: true)
        for branch in repo.branches where branch.ref?.isBranch == true {
            let item = SidebarItem(title: branch.ref?.shortName ?? "", isGroup: false)
            item.revSpecifier = branch
            branchesItem.children.append(item)
        }
        if !branchesItem.children.isEmpty {
            rootItems.append(branchesItem)
        }

        // Remotes section
        let remotesItem = SidebarItem(title: "Remotes", isGroup: true)
        var remoteGroups: [String: SidebarItem] = [:]

        for branch in repo.branches where branch.ref?.isRemoteBranch == true {
            if let remoteName = branch.ref?.remoteName {
                if remoteGroups[remoteName] == nil {
                    let remoteItem = SidebarItem(title: remoteName, isGroup: true)
                    remoteGroups[remoteName] = remoteItem
                }
                let item = SidebarItem(title: branch.ref?.remoteBranchName ?? "", isGroup: false)
                item.revSpecifier = branch
                remoteGroups[remoteName]?.children.append(item)
            }
        }

        for (_, remoteItem) in remoteGroups.sorted(by: { $0.key < $1.key }) {
            remotesItem.children.append(remoteItem)
        }
        if !remotesItem.children.isEmpty {
            rootItems.append(remotesItem)
        }

        // Tags section
        let tagsItem = SidebarItem(title: "Tags", isGroup: true)
        for branch in repo.branches where branch.ref?.isTag == true {
            let item = SidebarItem(title: branch.ref?.shortName ?? "", isGroup: false)
            item.revSpecifier = branch
            tagsItem.children.append(item)
        }
        if !tagsItem.children.isEmpty {
            rootItems.append(tagsItem)
        }
    }
}

// MARK: - Sidebar Item

public class SidebarItem: NSObject, ParentAccessible {
    @objc public var title: String
    @objc public var isGroup: Bool
    @objc public var children: [SidebarItem] = []
    @objc public var revSpecifier: GitRevSpecifier?
    @objc public weak var parentItem: SidebarItem?

    public var parent: ParentAccessible? {
        return parentItem
    }

    public init(title: String, isGroup: Bool) {
        self.title = title
        self.isGroup = isGroup
        super.init()
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarView: NSOutlineViewDataSource {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootItems.count
        }
        if let sidebarItem = item as? SidebarItem {
            return sidebarItem.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootItems[index]
        }
        if let sidebarItem = item as? SidebarItem {
            return sidebarItem.children[index]
        }
        return NSNull()
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let sidebarItem = item as? SidebarItem {
            return !sidebarItem.children.isEmpty
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarView: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let sidebarItem = item as? SidebarItem else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.frame = NSRect(x: 0, y: 0, width: 200, height: 17)
            textField.autoresizingMask = [.width]
            cellView?.addSubview(textField)
            cellView?.textField = textField
        }

        cellView?.textField?.stringValue = sidebarItem.title

        if sidebarItem.isGroup {
            cellView?.textField?.font = NSFont.boldSystemFont(ofSize: 11)
            cellView?.textField?.textColor = .secondaryLabelColor
        } else {
            cellView?.textField?.font = NSFont.systemFont(ofSize: 13)
            cellView?.textField?.textColor = .labelColor
        }

        return cellView
    }

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let sidebarItem = item as? SidebarItem {
            return sidebarItem.isGroup && sidebarItem.parentItem == nil
        }
        return false
    }
}
