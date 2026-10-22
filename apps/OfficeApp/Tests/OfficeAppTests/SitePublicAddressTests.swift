// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SitePublicAddressTests: XCTestCase {
    func testRootAndProjectRoutesUseWebsiteOriginOnce() {
        XCTAssertEqual(SitePublicAddress.url(website: "https://example.org", route: "/")?.absoluteString,
                       "https://example.org/")
        for website in ["https://EXAMPLE.org/handbook", "https://example.org/handbook/"] {
            XCTAssertEqual(SitePublicAddress.url(website: website, route: "/handbook/chapter/")?.absoluteString,
                           "https://example.org/handbook/chapter/")
        }
    }

    func testBuildBaseOverridesWebsitePathWithoutDuplicatingIt() {
        XCTAssertEqual(SitePublicAddress.url(website: "https://example.org/old/", route: "/new/chapter/")?.absoluteString,
                       "https://example.org/new/chapter/")
        XCTAssertEqual(SitePublicAddress.url(website: "https://example.org/old/", route: "/")?.absoluteString,
                       "https://example.org/")
    }

    func testUnicodeRoutesAreEncodedAndHTTPPortsArePreserved() {
        XCTAssertEqual(SitePublicAddress.url(website: "http://localhost:8090/handbook/", route: "/handbook/café/")?.absoluteString,
                       "http://localhost:8090/handbook/caf%C3%A9/")
    }

    func testMissingUnsafeAndAmbiguousWebsiteAddressesAreOmitted() {
        let websites: [String?] = [nil, "", "   ", "/relative/", "example.org", "ftp://example.org",
                                  "https://user:secret@example.org/", "https://example.org/?token=secret",
                                  "https://example.org/#fragment", "https://example.org:99999"]
        for website in websites {
            XCTAssertNil(SitePublicAddress.url(website: website, route: "/page/"), "\(website ?? "nil")")
        }
        for route in ["relative", "//other.org/", "/a/../b/", "/page/?secret", "/page/#fragment", "/a\\b/", "/bad\npath/"] {
            XCTAssertNil(SitePublicAddress.url(website: "https://example.org/", route: route), route)
        }
    }

    func testShellUsesOneAddressForCanonicalAndLinkPreview() throws {
        let canonical = try XCTUnwrap(SitePublicAddress.url(website: "https://example.org/book/", route: "/book/chapter/"))
        let html = SiteShellPage.render(template: "<html><head><title>Reader</title></head><body></body></html>",
                                        base: "/book/", route: "/book/chapter/", title: "Chapter", siteTitle: "Book",
                                        description: "", text: "", canonical: canonical)
        XCTAssertTrue(html.contains(#"<link rel="canonical" href="https://example.org/book/chapter/">"#))
        XCTAssertTrue(html.contains(#"<meta property="og:url" content="https://example.org/book/chapter/">"#))
        XCTAssertFalse(html.contains(#"name="robots""#))
    }

    func testMissingPageCannotClaimAnIndexableCanonicalAddress() throws {
        let canonical = try XCTUnwrap(URL(string: "https://example.org/"))
        let html = SiteShellPage.render(template: "<html><head><title>Reader</title></head><body></body></html>",
                                        base: "/", route: "/", title: "Book", siteTitle: "Book",
                                        description: "", text: "", canonical: canonical, indexable: false)
        XCTAssertTrue(html.contains(#"<meta name="robots" content="noindex">"#))
        XCTAssertFalse(html.contains(#"rel="canonical""#))
        XCTAssertFalse(html.contains(#"property="og:url""#))
    }
}
