//
//  FileHandle+ReadLine.swift
//  GitX
//
//  Swift conversion of NSFileHandleExt
//  Original by Michael Stapelberg, 2007
//  BSD License
//

import Foundation

public extension FileHandle {

    func readLine() -> String? {
        var lineData = Data()
        let bufferSize = 1

        while true {
            let chunk = readData(ofLength: bufferSize)

            if chunk.isEmpty {
                break
            }

            if let byte = chunk.first {
                if byte == UInt8(ascii: "\n") {
                    break
                }
                if byte == UInt8(ascii: "\r") {
                    continue
                }
                lineData.append(chunk)
            }
        }

        if lineData.isEmpty {
            return nil
        }

        return String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .isoLatin1)
    }
}
