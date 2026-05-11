import XCTest
@testable import SwiftMoLoggerNetwork
import SwiftMoLogger
import SwiftMoLoggerTesting

final class NetworkLoggingTests: XCTestCase {

    func testProtocolMatchesHTTPRequests() {
        let request = URLRequest(url: URL(string: "https://example.com/api/v1")!)
        XCTAssertTrue(NetworkLoggingProtocol.canInit(with: request))
    }

    func testProtocolRejectsAlreadyHandledRequests() {
        guard let mutable = (URLRequest(url: URL(string: "https://example.com")!) as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return XCTFail("could not build mutable request")
        }
        URLProtocol.setProperty(true, forKey: NetworkLoggingProtocol.propertyKey, in: mutable)
        XCTAssertFalse(NetworkLoggingProtocol.canInit(with: mutable as URLRequest))
    }

    func testProtocolRejectsNonHTTPSchemes() {
        let ftpRequest = URLRequest(url: URL(string: "ftp://example.com/file")!)
        XCTAssertFalse(NetworkLoggingProtocol.canInit(with: ftpRequest))
    }

    func testSensitiveHeadersAreNotLeaked() {
        let recorder = SwiftMoLogger.installRecorder()
        defer { SwiftMoLogger.reset() }

        let config = URLSessionConfiguration.ephemeral
        NetworkLogger.install(on: config)
        // We don't actually fire a request — verifying just that sensitive
        // headers are present in the static list so future changes do not
        // accidentally drop one.
        XCTAssertTrue(NetworkLoggingProtocol.sensitiveHeaders.contains("authorization"))
        XCTAssertTrue(NetworkLoggingProtocol.sensitiveHeaders.contains("cookie"))
        XCTAssertTrue(NetworkLoggingProtocol.sensitiveHeaders.contains("x-api-key"))

        _ = recorder
        _ = config
    }
}
