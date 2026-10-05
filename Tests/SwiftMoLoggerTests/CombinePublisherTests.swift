#if canImport(Combine)
import XCTest
import Combine
@testable import SwiftMoLogger

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class CombinePublisherTests: LoggingTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        cancellables.removeAll()
    }

    func testPublisherReceivesEntries() {
        let received = expectation(description: "publisher")
        received.expectedFulfillmentCount = 3

        let combine = CombineLogPublisher()
        registry.addEngine(combine)
        combine.publisher
            .sink { _ in received.fulfill() }
            .store(in: &cancellables)

        log.info("one")
        log.warning("two")
        log.error("three")

        wait(for: [received], timeout: 1)
    }
}
#endif
