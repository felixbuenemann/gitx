//
//  PersistentSplitView.swift
//  GitX
//
//  Split views that persist their divider positions
//

import SwiftUI
import AppKit

// MARK: - Persistent VSplitView

struct PersistentVSplitView<Top: View, Bottom: View>: NSViewControllerRepresentable {
    let autosaveName: String
    let top: Top
    let bottom: Bottom
    var topMinHeight: CGFloat = 100
    var bottomMinHeight: CGFloat = 100

    init(
        autosaveName: String,
        topMinHeight: CGFloat = 100,
        bottomMinHeight: CGFloat = 100,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.autosaveName = autosaveName
        self.topMinHeight = topMinHeight
        self.bottomMinHeight = bottomMinHeight
        self.top = top()
        self.bottom = bottom()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = false
        controller.splitView.autosaveName = autosaveName

        let topItem = NSSplitViewItem(viewController: NSHostingController(rootView: top))
        topItem.minimumThickness = topMinHeight
        topItem.holdingPriority = .defaultLow

        let bottomItem = NSSplitViewItem(viewController: NSHostingController(rootView: bottom))
        bottomItem.minimumThickness = bottomMinHeight
        bottomItem.holdingPriority = .defaultLow

        controller.addSplitViewItem(topItem)
        controller.addSplitViewItem(bottomItem)

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        if let topVC = controller.splitViewItems.first?.viewController as? NSHostingController<Top> {
            topVC.rootView = top
        }
        if let bottomVC = controller.splitViewItems.last?.viewController as? NSHostingController<Bottom> {
            bottomVC.rootView = bottom
        }
    }
}

// MARK: - Persistent HSplitView

struct PersistentHSplitView<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let autosaveName: String
    let leading: Leading
    let trailing: Trailing
    var leadingMinWidth: CGFloat = 100
    var trailingMinWidth: CGFloat = 100

    init(
        autosaveName: String,
        leadingMinWidth: CGFloat = 100,
        trailingMinWidth: CGFloat = 100,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.autosaveName = autosaveName
        self.leadingMinWidth = leadingMinWidth
        self.trailingMinWidth = trailingMinWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.autosaveName = autosaveName

        let leadingItem = NSSplitViewItem(viewController: NSHostingController(rootView: leading))
        leadingItem.minimumThickness = leadingMinWidth
        leadingItem.holdingPriority = .defaultLow

        let trailingItem = NSSplitViewItem(viewController: NSHostingController(rootView: trailing))
        trailingItem.minimumThickness = trailingMinWidth
        trailingItem.holdingPriority = .defaultLow

        controller.addSplitViewItem(leadingItem)
        controller.addSplitViewItem(trailingItem)

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        if let leadingVC = controller.splitViewItems.first?.viewController as? NSHostingController<Leading> {
            leadingVC.rootView = leading
        }
        if let trailingVC = controller.splitViewItems.last?.viewController as? NSHostingController<Trailing> {
            trailingVC.rootView = trailing
        }
    }
}
