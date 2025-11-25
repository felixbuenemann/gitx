//
//  String+RegEx.swift
//  GitX
//
//  Swift conversion of NSString_RegEx
//  Original by John R Chang on 2005-11-08
//  Creative Commons Public Domain
//

import Foundation

public extension String {

    struct RegexOptions: OptionSet {
        public let rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        public static let caseInsensitive = RegexOptions(rawValue: REG_ICASE)
        public static let newline = RegexOptions(rawValue: REG_NEWLINE)
    }

    struct RegexMatch {
        public let fullMatch: String
        public let range: Range<String.Index>
        public let captures: [String]
        public let captureRanges: [Range<String.Index>]
    }

    func matches(pattern: String, options: RegexOptions = []) -> Bool {
        do {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: options.contains(.caseInsensitive) ? [.caseInsensitive] : []
            )
            let range = NSRange(self.startIndex..., in: self)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    func substrings(matching pattern: String, options: RegexOptions = []) throws -> [RegexMatch] {
        var regexOptions: NSRegularExpression.Options = []
        if options.contains(.caseInsensitive) {
            regexOptions.insert(.caseInsensitive)
        }

        let regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        let range = NSRange(self.startIndex..., in: self)
        let matches = regex.matches(in: self, options: [], range: range)

        return matches.compactMap { match -> RegexMatch? in
            guard let fullRange = Range(match.range, in: self) else { return nil }
            let fullMatch = String(self[fullRange])

            var captures: [String] = []
            var captureRanges: [Range<String.Index>] = []

            for i in 1..<match.numberOfRanges {
                let captureNSRange = match.range(at: i)
                if captureNSRange.location != NSNotFound,
                   let captureRange = Range(captureNSRange, in: self) {
                    captures.append(String(self[captureRange]))
                    captureRanges.append(captureRange)
                }
            }

            return RegexMatch(
                fullMatch: fullMatch,
                range: fullRange,
                captures: captures,
                captureRanges: captureRanges
            )
        }
    }

    func grep(_ pattern: String, options: RegexOptions = []) -> Bool {
        return matches(pattern: pattern, options: options)
    }

    func firstMatch(pattern: String, options: RegexOptions = []) -> String? {
        do {
            let matches = try substrings(matching: pattern, options: options)
            return matches.first?.fullMatch
        } catch {
            return nil
        }
    }

    func captureGroups(pattern: String, options: RegexOptions = []) -> [String]? {
        do {
            let matches = try substrings(matching: pattern, options: options)
            guard let firstMatch = matches.first else { return nil }
            return [firstMatch.fullMatch] + firstMatch.captures
        } catch {
            return nil
        }
    }
}
