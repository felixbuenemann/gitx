//
//  DiffView.swift
//  GitX
//
//  Diff display view
//

import AppKit
import WebKit

@objc public class DiffView: NSView {

    // MARK: - Properties

    private var webView: WKWebView!
    @objc public var diffText: String = "" {
        didSet {
            renderDiff()
        }
    }

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    // MARK: - Rendering

    private func renderDiff() {
        let html = generateDiffHTML(from: diffText)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func generateDiffHTML(from diff: String) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', Menlo, monospace;
            font-size: 12px;
            margin: 0;
            padding: 10px;
            background: #ffffff;
        }
        pre {
            margin: 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .line { line-height: 1.4; }
        .add { background-color: #e6ffec; color: #24292e; }
        .del { background-color: #ffebe9; color: #24292e; }
        .header { color: #6f42c1; font-weight: bold; }
        .hunk { color: #0366d6; background-color: #f1f8ff; }
        @media (prefers-color-scheme: dark) {
            body { background: #1e1e1e; color: #d4d4d4; }
            .add { background-color: #2ea04326; color: #d4d4d4; }
            .del { background-color: #f8514926; color: #d4d4d4; }
            .header { color: #b392f0; }
            .hunk { color: #79b8ff; background-color: #1f6feb26; }
        }
        </style>
        </head>
        <body>
        <pre>
        """

        for line in diff.components(separatedBy: "\n") {
            let escapedLine = escapeHTML(line)

            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") {
                html += "<span class=\"line header\">\(escapedLine)</span>\n"
            } else if line.hasPrefix("@@") {
                html += "<span class=\"line hunk\">\(escapedLine)</span>\n"
            } else if line.hasPrefix("+") {
                html += "<span class=\"line add\">\(escapedLine)</span>\n"
            } else if line.hasPrefix("-") {
                html += "<span class=\"line del\">\(escapedLine)</span>\n"
            } else {
                html += "<span class=\"line\">\(escapedLine)</span>\n"
            }
        }

        html += """
        </pre>
        </body>
        </html>
        """

        return html
    }

    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
