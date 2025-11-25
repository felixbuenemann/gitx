//
//  EasyFS.swift
//  GitX
//
//  Swift conversion of PBEasyFS
//  Original by Pieter de Bie on 6/17/08
//

import Foundation

public enum EasyFS {

    public static func fileExists(atPath path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    public static func directoryExists(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    public static func temporaryFile(withSuffix suffix: String) -> URL {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("XXXXXX\(suffix)")

        var templatePath = template.path
        let result = templatePath.withUTF8 { buffer -> String in
            var mutableBuffer = Array(buffer)
            mutableBuffer.append(0) // null terminator

            return mutableBuffer.withUnsafeMutableBufferPointer { ptr -> String in
                guard let baseAddress = ptr.baseAddress else { return template.path }
                let cString = UnsafeMutablePointer(OpaquePointer(baseAddress))
                let fd = mkstemps(cString, Int32(suffix.count))
                close(fd)
                return String(cString: cString)
            }
        }

        return URL(fileURLWithPath: result)
    }

    public static func temporaryDirectory(withPrefix prefix: String) -> URL {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix).XXXXXX")

        var templatePath = template.path
        let result = templatePath.withUTF8 { buffer -> String in
            var mutableBuffer = Array(buffer)
            mutableBuffer.append(0) // null terminator

            return mutableBuffer.withUnsafeMutableBufferPointer { ptr -> String in
                guard let baseAddress = ptr.baseAddress else { return template.path }
                let cString = UnsafeMutablePointer(OpaquePointer(baseAddress))
                guard let resultPtr = mkdtemp(cString) else { return template.path }
                return String(cString: resultPtr)
            }
        }

        return URL(fileURLWithPath: result)
    }
}
