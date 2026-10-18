// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one page the server serves for every wiki URL: the app's index.html
// with the title and first paragraph in meta tags, so a link pasted into
// chat unfurls, and the route the app should open. The body is the canvas;
// nothing of the page is rendered as HTML (docs/plans/wiki.md, Decisions).

import Foundation

struct Shell: Sendable {
    /// The app's index.html as built by build/web-app.sh, with the
    /// `initialRoute` and meta tags still to be filled.
    let template: String

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    func render(route: String, title: String, description: String, url: String) -> String {
        let desc = description.replacingOccurrences(of: "\n", with: " ").prefix(300)
        let meta = """
        <meta property="og:type" content="article">
        <meta property="og:title" content="\(Shell.escape(title))">
        <meta property="og:description" content="\(Shell.escape(String(desc)))">
        <meta property="og:url" content="\(Shell.escape(url))">
        <meta name="description" content="\(Shell.escape(String(desc)))">
        <meta name="starling-route" content="\(Shell.escape(route))">
        """
        var html = template
        if let r = html.range(of: "<title>") { html.replaceSubrange(r, with: meta + "<title>") }
        else if let r = html.range(of: "</head>") { html.replaceSubrange(r, with: meta + "</head>") }
        if let r = html.range(of: #"<title>[^<]*</title>"#, options: .regularExpression) {
            html.replaceSubrange(r, with: "<title>\(Shell.escape(title))</title>")
        }
        return html
    }
}
