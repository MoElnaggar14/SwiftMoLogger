#if canImport(Combine)
import XCTest
import Combine
@testable import SwiftMoLogger

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class CombinePublisherTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        SwiftMoLogger.reset()
        cancellables.removeAll()
    }

    func testPublisherReceivesEntries() {
        let received = expectation(description: "publisher")
        received.expectedFulfillmentCount = 3

        SwiftMoLogger.publisher()
            .sink { _ in received.fulfill() }
            .store(in: &cancellables)

        SwiftMoLogger.info("one")
        SwiftMoLogger.warn("two")
        SwiftMoLogger.error("three")

        wait(for: [received], timeout: 1)
    }
}
#endif
