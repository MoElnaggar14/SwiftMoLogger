import Foundation
import SwiftMoLogger

/// `URLProtocol` subclass that captures every `URLSession` request that
/// passes through a session configured with ``NetworkLogger/install(on:)``.
///
/// For each request it emits a structured ``LogEntry`` with:
/// - HTTP method, URL, query, status code, duration_ms, response_bytes
/// - automatic tagging (`.api`)
/// - automatic redaction of `Authorization`, `Cookie`, `Set-Cookie`,
///   `X-API-Key`, and any header whose name matches a custom rule
/// - breadcrumb so the request is part of the crash trail
///
/// Implementation forwards every call to a child `URLSession` configured
/// without the protocol installed, avoiding infinite recursion.
public final class NetworkLoggingProtocol: URLProtocol, @unchecked Sendable {
    public static let propertyKey = "swiftmologger.network.handled"

    /// Header names whose values are stripped before logging.
    public static var sensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token", "proxy-authorization"
    ]

    private var dataTask: URLSessionDataTask?
    private var receivedData = Data()
    private var startTime: DispatchTime = .now()
    private static let childSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        return URLSession(configuration: config)
    }()

    public override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: propertyKey, in: request) != nil {
            return false
        }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        startTime = DispatchTime.now()
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: NetworkLoggingProtocol.propertyKey, in: mutable)

        logRequest(mutable as URLRequest)
        SwiftMoLogger.breadcrumb(
            "→ \(mutable.httpMethod ?? "?") \(mutable.url?.absoluteString ?? "?")",
            category: .network
        )

        dataTask = NetworkLoggingProtocol.childSession.dataTask(with: mutable as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            self.finish(data: data, response: response, error: error)
        }
        dataTask?.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - Private

    private func finish(data: Data?, response: URLResponse?, error: Error?) {
        let elapsedNS = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedMS = Double(elapsedNS) / 1_000_000

        if let error = error {
            logFailure(error: error, elapsedMS: elapsedMS)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = data {
            client?.urlProtocol(self, didLoad: data)
        }
        logResponse(data: data, response: response, elapsedMS: elapsedMS)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func logRequest(_ request: URLRequest) {
        let metadata: LogMetadata = [
            "http.method": .string(request.httpMethod ?? "?"),
            "http.url": .string(request.url?.absoluteString ?? "?"),
            "http.headers": .string(Self.sanitiseHeaders(request.allHTTPHeaderFields ?? [:])),
            "http.body_bytes": .int(Int64(request.httpBody?.count ?? 0))
        ]
        SwiftMoLogger.info("HTTP request", tag: .api, metadata: metadata)
    }

    private func logResponse(data: Data?, response: URLResponse?, elapsedMS: Double) {
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode ?? 0
        let level: LogLevel = status >= 500 ? .error : (status >= 400 ? .warning : .info)
        let metadata: LogMetadata = [
            "http.url": .string(response?.url?.absoluteString ?? "?"),
            "http.status": .int(Int64(status)),
            "http.response_bytes": .int(Int64(data?.count ?? 0)),
            "http.duration_ms": .double(elapsedMS)
        ]
        SwiftMoLogger.log(level, "HTTP response", tag: .api, metadata: metadata)
        SwiftMoLogger.breadcrumb(
            "← \(status) \(response?.url?.lastPathComponent ?? "?") (\(Int(elapsedMS))ms)",
            category: .network
        )
    }

    private func logFailure(error: Error, elapsedMS: Double) {
        SwiftMoLogger.error("HTTP failure", tag: .api, metadata: [
            "http.url": .string(request.url?.absoluteString ?? "?"),
            "http.duration_ms": .double(elapsedMS),
            "error": .string(String(describing: error))
        ])
        SwiftMoLogger.breadcrumb(
            "✗ \(request.url?.host ?? "?"): \(error.localizedDescription)",
            category: .network
        )
    }

    private static func sanitiseHeaders(_ headers: [String: String]) -> String {
        let pairs = headers.map { (key, value) -> String in
            sensitiveHeaders.contains(key.lowercased()) ? "\(key)=[REDACTED]" : "\(key)=\(value)"
        }
        return pairs.sorted().joined(separator: " ")
    }
}

/// Façade for installing automatic network logging.
public enum NetworkLogger {
    /// Install the URLProtocol on a session configuration. Call once at
    /// app startup before constructing any `URLSession`:
    ///
    /// ```swift
    /// let config = URLSessionConfiguration.default
    /// NetworkLogger.install(on: config)
    /// let session = URLSession(configuration: config)
    /// ```
    public static func install(on configuration: URLSessionConfiguration) {
        var classes = configuration.protocolClasses ?? []
        classes.insert(NetworkLoggingProtocol.self, at: 0)
        configuration.protocolClasses = classes
    }

    /// Install on the shared session — irreversible until app restart, so
    /// only use for the singleton case.
    public static func installOnSharedSession() {
        URLProtocol.registerClass(NetworkLoggingProtocol.self)
    }
}
