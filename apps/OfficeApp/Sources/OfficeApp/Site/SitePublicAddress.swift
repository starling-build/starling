// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Public metadata uses the configured website's origin and the build's route.
/// In particular, a project path must not be appended twice.
enum SitePublicAddress {
    static func url(website: String?, route: String) -> URL? {
        guard let website, !website.trimmingWhitespace().isEmpty,
              var parts = URLComponents(string: website.trimmingWhitespace()),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              route.hasPrefix("/"), !route.contains("//"),
              !route.contains(where: { $0 == "?" || $0 == "#" || $0 == "\\" || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }),
              !route.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        if let port = parts.port, !(1...65535).contains(port) { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = route
        return parts.url
    }
}
#endif
