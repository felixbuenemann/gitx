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

        var templateBytes = Array(template.path.utf8CString)
        let fd = mkstemps(&templateBytes, Int32(suffix.count))
        close(fd)
        let resultPath = String(cString: templateBytes)
        return URL(fileURLWithPath: resultPath)
    }

    public static func temporaryDirectory(withPrefix prefix: String) -> URL {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix).XXXXXX")

        var templateBytes = Array(template.path.utf8CString)
        guard mkdtemp(&templateBytes) != nil else {
            return template
        }
        let resultPath = String(cString: templateBytes)
        return URL(fileURLWithPath: resultPath)
    }
}
