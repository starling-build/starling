// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// How the client reaches the server: the browser's fetch in a tab (same
// origin, cookie rides along), URLSession natively. Both answer on the
// main thread with a status and bytes.

import Foundation
#if os(WASI)
import FlutterWeb
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct WikiResponse {
    var status: Int
    var body: Data
    var ok: Bool { (200 ..< 300).contains(status) }
    var text: String { String(decoding: body, as: UTF8.self) }
    /// The server's `message` on an error, or the raw text.
    var message: String {
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = obj["message"] as? String { return m }
        }
        return text.isEmpty ? "HTTP \(status)" : String(text.prefix(200))
    }
}

protocol WikiTransport {
    func request(_ method: String, _ url: String, body: Data?, contentType: String?, _ completion: @escaping (WikiResponse) -> Void)
}

#if os(WASI)
struct WebTransport: WikiTransport {
    func request(_ method: String, _ url: String, body: Data?, contentType: String?, _ completion: @escaping (WikiResponse) -> Void) {
        var headers: [String: String] = ["accept": "application/json"]
        if let contentType { headers["content-type"] = contentType }
        WebHTTP.request(method, url, headers: headers, body: body) { r in
            completion(WikiResponse(status: r.status, body: r.body))
        }
    }
}
#else
final class NativeTransport: WikiTransport {
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        return URLSession(configuration: c)
    }()

    func request(_ method: String, _ url: String, body: Data?, contentType: String?, _ completion: @escaping (WikiResponse) -> Void) {
        guard let u = URL(string: url) else { completion(WikiResponse(status: 0, body: Data("bad url \(url)".utf8))); return }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "content-type") }
        session.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bytes = data ?? Data((error.map { "\($0)" } ?? "").utf8)
            DispatchQueue.main.async { completion(WikiResponse(status: status, body: bytes)) }
        }.resume()
    }
}
#endif
