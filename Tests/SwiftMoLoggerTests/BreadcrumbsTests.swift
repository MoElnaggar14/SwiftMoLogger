import XCTest
@testable import SwiftMoLogger

final class BreadcrumbsTests: LoggingTestCase {
    override func setUp() {
        super.setUp()
        environment.breadcrumbs.clear()
    }

    func testBreadcrumbsAreRecordedAndSnapshotted() {
        environment.breadcrumbs.record("opened cart", category: .userAction)
        environment.breadcrumbs.record("nav to checkout", category: .navigation)
        let crumbs = environment.breadcrumbs.snapshot()
        XCTAssertEqual(crumbs.count, 2)
        XCTAssertEqual(crumbs[0].category, .userAction)
        XCTAssertEqual(crumbs[1].category, .navigation)
    }

    func testBreadcrumbsAreBoundedByCapacity() {
        let store = BreadcrumbStore(capacity: 3)
        for index in 0..<10 {
            store.record(Breadcrumb(category: .custom, message: "crumb-\(index)"))
        }
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.map(\.message), ["crumb-7", "crumb-8", "crumb-9"])
    }

    func testBreadcrumbCarriesMetadata() {
        environment.breadcrumbs.record("tapped Buy", category: .userAction, metadata: ["sku": "ABC-1"])
        let crumb = environment.breadcrumbs.snapshot().last
        XCTAssertEqual(crumb?.metadata["sku"], .string("ABC-1"))
    }
}
