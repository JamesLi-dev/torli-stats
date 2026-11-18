import Foundation
import SwiftUI

/// Configure once at launch, including when the executable runs as the update helper.
public struct PrivateUpdateChannel {
    public private(set) static var current: Self?
    let origin: URL
    let product: String
    let credential: () -> String?
    let credentialSettings: () -> AnyView

    public static func configure(origin: String, product: String, credential: @escaping () -> String?,
                                 credentialSettings: @escaping () -> AnyView) {
        guard let parts = URLComponents(string: origin), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.port == nil || (host == "localhost" && parts.port == 8787),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url,
              product == Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              product.range(of: #"\A[A-Za-z0-9]+\z"#, options: .regularExpression) != nil else { return }
        current = Self(origin: url, product: product, credential: credential, credentialSettings: credentialSettings)
    }

    var latest: URL { origin.appendingPathComponent("v1/pro/latest") }

    func releaseURL(_ version: String) -> URL {
        origin.appendingPathComponent("v1/pro/releases/v\(version)")
    }

    func release(from response: HTTPURLResponse) -> AppUpdateRelease? {
        guard response.url == latest, response.statusCode == 200,
              let version = response.value(forHTTPHeaderField: "X-Torli-Version"),
              version.range(of: #"\A(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}\z"#, options: .regularExpression) != nil else { return nil }
        return AppUpdateRelease(version: version, downloadURL: releaseURL(version), publishedAt: nil)
    }

    func authorize(_ request: inout URLRequest) throws {
        guard let url = request.url, url.scheme == "https", url.host == origin.host, url.port == origin.port,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.hasPrefix("/v1/pro/"),
              let token = credential(), !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }
}

final class RefuseUpdateRedirect: NSObject, URLSessionTaskDelegate {
    static let shared = RefuseUpdateRedirect()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
