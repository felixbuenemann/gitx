//
//  GitXApp.swift
//  GitX
//
//  Main application entry point
//

import AppKit

@main
struct GitXApp {
    static func main() {
        // Register defaults
        GitDefaults.registerDefaults()

        // Create and run application
        let app = NSApplication.shared
        let delegate = ApplicationController()
        app.delegate = delegate

        // Run the application
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
