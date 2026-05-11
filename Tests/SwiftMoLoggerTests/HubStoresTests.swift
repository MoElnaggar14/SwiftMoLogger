import XCTest
@testable import SwiftMoLogger

final class HubStoresTests: XCTestCase {

    func testNetworkEventStoreBoundedByCapacity() {
        let store = NetworkEventStore(capacity: 3)
        let url = URL(string: "https://example.com")!
        for index in 0..<10 {
            store.record(NetworkEvent(
                startedAt: Date(),
                endedAt: Date(),
                method: "GET",
                url: url,
                statusCode: 200,
                responseBytes: Int64(index),
                requestBytes: 0
            ))
        }
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.map(\.responseBytes), [7, 8, 9])
    }

    func testSignpostEventStoreOrdering() {
        let store = SignpostEventStore(capacity: 5)
        let now = Date()
        store.record(SignpostEvent(name: "a", startedAt: now, endedAt: now.addingTimeInterval(0.01)))
        store.record(SignpostEvent(name: "b", startedAt: now.addingTimeInterval(0.02), endedAt: now.addingTimeInterval(0.03)))
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.map(\.name), ["a", "b"])
    }

    func testVitalsHistoryStore() {
        let store = VitalsHistoryStore(capacity: 4)
        for index in 0..<10 {
            store.record(VitalsTick(
                memoryMB: Double(index),
                cpuPercent: 5,
                fps: 60,
                thermalState: "nominal",
                batteryLevel: 0.9
            ))
        }
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 4)
        XCTAssertEqual(snapshot.map(\.memoryMB), [6, 7, 8, 9])
    }
}
