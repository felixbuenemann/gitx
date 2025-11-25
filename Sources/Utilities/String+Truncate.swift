//
//  String+Truncate.swift
//  GitX
//
//  Swift conversion of NSString_Truncate
//  Original by Andre Berg on 24.03.10
//  Copyright 2010 Berg Media. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0
//

import Foundation

public enum TruncateMode {
    case center
    case start
    case end
}

public extension String {

    func truncated(to length: Int, mode: TruncateMode = .end, indicator: String = "...") -> String {
        guard self.count > length else { return self }
        guard length > indicator.count else { return indicator }

        let availableLength = length - indicator.count

        switch mode {
        case .center:
            let halfLength = availableLength / 2
            let leftEnd = self.index(self.startIndex, offsetBy: halfLength)
            let rightStart = self.index(self.endIndex, offsetBy: -(availableLength - halfLength))
            return String(self[..<leftEnd]) + indicator + String(self[rightStart...])

        case .start:
            let start = self.index(self.endIndex, offsetBy: -availableLength)
            return indicator + String(self[start...])

        case .end:
            let end = self.index(self.startIndex, offsetBy: availableLength)
            return String(self[..<end]) + indicator
        }
    }
}
