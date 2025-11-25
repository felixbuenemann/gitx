//
//  OutlineView+ExpandParents.swift
//  GitX
//
//  Swift conversion of NSOutlineViewExt
//  Original by Pieter de Bie on 9/9/09
//

import AppKit

public protocol ParentAccessible: AnyObject {
    var parent: ParentAccessible? { get }
}

public extension NSOutlineView {

    func expandItem(_ item: Any?, expandParents: Bool) {
        guard expandParents else {
            expandItem(item)
            return
        }

        var parents: [Any] = []
        var current: Any? = item

        while let currentItem = current {
            parents.insert(currentItem, at: 0)
            if let accessible = currentItem as? ParentAccessible {
                current = accessible.parent
            } else {
                break
            }
        }

        for parent in parents {
            expandItem(parent)
        }
    }
}
