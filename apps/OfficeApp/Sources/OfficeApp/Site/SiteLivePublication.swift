// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if !os(WASI)
/// A point-in-time check of a public build marker, not a visual rendering audit.
enum SiteLivePublication {
    static let markerFile = "starling-publication.json"
    struct Marker: Codable, Equatable {
        let version: Int
        let build: String
    }
    struct Snapshot: Equatable {
        let receipt: SitePublicationState.Receipt
        let website: URL
        let marker: Marker
    }

    static func snapshot(repo: String, out: String) throws -> Snapshot {
        let receipt: SitePublicationState.Receipt
        do { receipt = try SitePublicationState.matchingReceipt(repo: repo, out: out) }
        catch { throw SiteError("Publish this publication from this device before checking its website.") }
        func sentFile(_ path: String) throws -> Data {
            let result = LocalSiteStore.git(["show", receipt.revision + ":" + path], in: repo)
            guard result.status == 0 else { throw SiteError("Publish again to enable checking this website's version.") }
            return Data(result.output.utf8)
        }
        let config = try JSONDecoder().decode(SiteConfig.self, from: sentFile(SiteFiles.config))
        let current = try SiteBuilder.readConfig(repo)
        func address(_ config: SiteConfig) throws -> String {
            let settings = try SiteHosting.Settings(title: config.title, repository: "", url: config.url ?? "")
            guard let url = settings.url, settings.base == SiteFiles.normalizedBase(config.base) else {
                throw SiteError("Set the website address in Publishing settings, then publish again.")
            }
            return url
        }
        let url = try address(config)
        guard try address(current) == url else {
            throw SiteError("The website address changed. Publish to the new address before checking it.")
        }
        let markerData = try sentFile(out + "/" + markerFile)
        guard let marker = try? JSONDecoder().decode(Marker.self, from: markerData),
              marker.version == 1, UUID(uuidString: marker.build) != nil, let website = URL(string: url) else {
            throw SiteError("Publish again to enable checking this website's version.")
        }
        return Snapshot(receipt: receipt, website: website, marker: marker)
    }

    /// Completion runs off the UI thread. Inject a session for offline HTTP tests.
    static func check(_ expected: Snapshot, session suppliedSession: URLSession? = nil,
                      completion: @escaping (Result<URL, SiteError>) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        let session = suppliedSession ?? URLSession(configuration: config)
        let markerURL = expected.website.appendingPathComponent(markerFile)
        var components = URLComponents(url: markerURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "check", value: UUID().uuidString)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            defer { if suppliedSession == nil { session.finishTasksAndInvalidate() } }
            guard error == nil, let response = response as? HTTPURLResponse else {
                completion(.failure(SiteError("Could not reach the website. Check your connection and try again."))); return
            }
            guard response.statusCode == 200 else {
                completion(.failure(SiteError("Website version is not available yet (HTTP \(response.statusCode)). Hosting may still be updating; try again shortly."))); return
            }
            guard let final = response.url, final.scheme == markerURL.scheme,
                  final.host == markerURL.host, final.port == markerURL.port, final.path == markerURL.path,
                  let data, data.count <= 16_384,
                  let actual = try? JSONDecoder().decode(Marker.self, from: data), actual == expected.marker else {
                completion(.failure(SiteError("The website has not confirmed this uploaded version. Wait for hosting to update, then check again."))); return
            }
            completion(.success(expected.website))
        }.resume()
    }
}
#endif
