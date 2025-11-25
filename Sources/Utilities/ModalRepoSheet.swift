//
//  ModalRepoSheet.swift
//  GitX
//
//  Swift conversion of RJModalRepoSheet
//  Original by Rowan James on 1/7/12
//  Copyright (c) 2012 Phere Development Pty. Ltd. All rights reserved.
//

import AppKit

@objc public class ModalRepoSheet: NSWindowController {

    public weak var repository: GitRepository?
    public weak var repositoryWindowController: GitWindowController?

    public init(nibName: NSNib.Name, repository: GitRepository) {
        super.init(window: nil)
        Bundle.main.loadNibNamed(nibName, owner: self, topLevelObjects: nil)
        self.repository = repository
        self.repositoryWindowController = repository.windowController
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func show() {
        repositoryWindowController?.showModalSheet(self)
    }

    public func hide() {
        repositoryWindowController?.hideModalSheet(self)
    }
}
