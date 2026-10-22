// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OfficeApp

/// Intercept HTTPS in-process: these tests never contact a real website.
private final class PublicationHTTP: URLProtocol {
    static var respond: ((URLRequest, URLProtocolClient, URLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.respond?(request, client!, self) }
    override func stopLoading() {}
}

final class SiteLivePublicationTests: XCTestCase {
    private let marker = SiteLivePublication.Marker(version: 1, build: "5F0FD699-F66D-4AF8-93BC-478E3BB7DA9C")
    private var expected: SiteLivePublication.Snapshot {
        .init(receipt: .init(version: 1, revision: String(repeating: "a", count: 40), destination: "local", target: "refs/heads/main", out: "docs"),
              website: URL(string: "https://author.example/handbook/")!, marker: marker)
    }

    private func check(body: Data, status: Int = 200, responseURL: URL? = nil, error: Error? = nil,
                       success: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PublicationHTTP.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); PublicationHTTP.respond = nil }
        PublicationHTTP.respond = { request, client, proto in
            XCTAssertEqual(request.url?.path, "/handbook/starling-publication.json", file: file, line: line)
            XCTAssertTrue(request.url?.query?.hasPrefix("check=") == true, file: file, line: line)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache", file: file, line: line)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
            if let error { client.urlProtocol(proto, didFailWithError: error); return }
            let response = HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: body)
            client.urlProtocolDidFinishLoading(proto)
        }
        let done = expectation(description: "Website checked")
        SiteLivePublication.check(expected, session: session) { result in
            switch result {
            case .success(let url):
                XCTAssertTrue(success, file: file, line: line)
                XCTAssertEqual(url, self.expected.website, file: file, line: line)
            case .failure: XCTAssertFalse(success, file: file, line: line)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testMatchingVersionConfirmsProjectWebsite() throws {
        check(body: try JSONEncoder().encode(marker), success: true)
    }

    func testOldUnknownMalformedAndOversizedResponsesDoNotConfirm() throws {
        check(body: try JSONEncoder().encode(SiteLivePublication.Marker(version: 1, build: UUID().uuidString)), success: false)
        check(body: try JSONEncoder().encode(SiteLivePublication.Marker(version: 2, build: marker.build)), success: false)
        check(body: Data("<html>Sign in</html>".utf8), success: false)
        check(body: Data(repeating: 32, count: 16_385) + (try JSONEncoder().encode(marker)), success: false)
    }

    func testUnavailableTimeoutAndDifferentAddressDoNotConfirm() throws {
        let data = try JSONEncoder().encode(marker)
        check(body: data, status: 404, success: false)
        check(body: data, status: 503, success: false)
        check(body: data, error: URLError(.timedOut), success: false)
        check(body: data, responseURL: URL(string: "https://other.example/handbook/starling-publication.json")!, success: false)
        check(body: data, responseURL: URL(string: "http://author.example/handbook/starling-publication.json")!, success: false)
    }

    private func withPublication(_ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try SiteCreation.create(title: "Handbook", parent: root.path)
        let settings = try SiteHosting.Settings(title: "Handbook", repository: "", url: expected.website.absoluteString)
        try SiteHosting.save(settings, repo: repo, expected: SiteHosting.load(repo: repo))
        try FileManager.default.createDirectory(atPath: repo + "/docs", withIntermediateDirectories: true)
        try JSONEncoder().encode(marker).write(to: URL(fileURLWithPath: repo + "/docs/" + SiteLivePublication.markerFile))
        for args in [["config", "user.name", "Test"], ["config", "user.email", "test@example.test"],
                     ["remote", "add", "origin", root.path + "/local.git"], ["add", "."], ["commit", "-qm", "Publication"]] {
            XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
        }
        let revision = LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace()
        try SitePublicationState.record(repo: repo, revision: revision,
                                        destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
        try body(repo)
    }

    func testExpectedVersionComesFromSentCommitDespiteLaterBuildAndEdits() throws {
        try withPublication { repo in
            let sent = try SiteLivePublication.snapshot(repo: repo, out: "docs")
            XCTAssertEqual(sent.marker, marker)
            try Data("later local build".utf8).write(to: URL(fileURLWithPath: repo + "/docs/" + SiteLivePublication.markerFile))
            var config = try SiteBuilder.readConfig(repo)
            config.title = "Unpublished title"
            try SiteBuilder.writeConfig(config, to: repo)
            _ = LocalSiteStore.git(["add", "."], in: repo)
            _ = LocalSiteStore.git(["commit", "-qm", "Not uploaded"], in: repo)
            XCTAssertEqual(try SiteLivePublication.snapshot(repo: repo, out: "docs"), sent)
            XCTAssertEqual(SitePublicationState.status(repo: repo), .pending)
        }
    }

    func testChangedAddressDestinationOrReceiptInvalidatesSnapshot() throws {
        try withPublication { repo in
            let original = try SiteHosting.load(repo: repo)
            let changed = try SiteHosting.Settings(title: "Handbook", repository: "", url: "https://author.example/new/")
            try SiteHosting.save(changed, repo: repo, expected: original)
            XCTAssertThrowsError(try SiteLivePublication.snapshot(repo: repo, out: "docs"))
            try original.bytes.write(to: URL(fileURLWithPath: repo + "/site.json"))
            XCTAssertThrowsError(try SiteLivePublication.snapshot(repo: repo, out: "different"))
            _ = LocalSiteStore.git(["remote", "set-url", "origin", "/other.git"], in: repo)
            XCTAssertThrowsError(try SiteLivePublication.snapshot(repo: repo, out: "docs"))
            try FileManager.default.removeItem(at: SitePublicationState.receiptURL(repo: repo))
            XCTAssertThrowsError(try SiteLivePublication.snapshot(repo: repo, out: "docs")) { error in
                XCTAssertEqual(String(describing: error), "Publish this publication from this device before checking its website.")
            }
        }
    }

    func testOlderPublicationNeedsFreshPublishForMarker() throws {
        try withPublication { repo in
            try FileManager.default.removeItem(atPath: repo + "/docs/" + SiteLivePublication.markerFile)
            _ = LocalSiteStore.git(["add", "-A"], in: repo)
            _ = LocalSiteStore.git(["commit", "-qm", "Older build"], in: repo)
            let revision = LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace()
            try SitePublicationState.record(repo: repo, revision: revision, destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
            XCTAssertThrowsError(try SiteLivePublication.snapshot(repo: repo, out: "docs"))
        }
    }
}
