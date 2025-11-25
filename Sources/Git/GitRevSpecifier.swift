//
//  GitRevSpecifier.swift
//  GitX
//
//  Swift conversion of PBGitRevSpecifier
//

import Foundation

@objc public class GitRevSpecifier: NSObject {

    @objc public var ref: GitRef?
    @objc public var parameters: [String]
    @objc public var workingDirectory: URL?

    @objc public var isSimpleRef: Bool {
        return ref != nil && parameters.isEmpty
    }

    @objc public init(ref: GitRef) {
        self.ref = ref
        self.parameters = []
        super.init()
    }

    @objc public init(parameters: [String]) {
        self.ref = nil
        self.parameters = parameters
        super.init()
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? GitRevSpecifier else { return false }

        if let ref = ref, let otherRef = other.ref {
            return ref.isEqualToRef(otherRef)
        }

        return parameters == other.parameters
    }

    public override var hash: Int {
        if let ref = ref {
            return ref.hash
        }
        return parameters.joined().hashValue
    }

    public override var description: String {
        if let ref = ref {
            return ref.shortName
        }
        return parameters.joined(separator: " ")
    }
}
