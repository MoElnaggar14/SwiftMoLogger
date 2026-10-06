import Foundation
import SwiftMoLogger
import Testing
@testable import SwiftMoLoggerMCPCore

@Suite("Device hub")
struct DeviceHubTests {
    @Test func storesEntriesWithIncreasingSequenceNumbers() async {
        let hub = DeviceHub()
        await hub.connect(sending: [Wire.entry("one"), Wire.entry("two", level: .error)])

        let all = await hub.search(LogQuery())
        #expect(all.entries.map(\.entry.message) == ["one", "two"])
        #expect(all.entries.map(\.seq) == [1, 2])
        #expect(all.nextSeq == 2)

        let errors = await hub.search(LogQuery(minLevel: .error))
        #expect(errors.entries.map(\.entry.message) == ["two"])
    }

    @Test func returnsTheNewestEntriesWhenTruncated() async {
        let hub = DeviceHub()
        await hub.connect(sending: (1...10).map { Wire.entry("entry \($0)") })
        let page = await hub.search(LogQuery(limit: 3))
        #expect(page.entries.map(\.entry.message) == ["entry 8", "entry 9", "entry 10"])
        #expect(page.truncated)
    }

    @Test func redactsBeforeStoringByDefault() async {
        let hub = DeviceHub()
        await hub.connect(sending: [Wire.entry("Signed in jane@example.com", metadata: ["email": "jane@example.com"])])
        let stored = await hub.search(LogQuery()).entries[0].entry
        #expect(!stored.message.contains("jane@example.com"))
        #expect(stored.metadata["email"]?.description.contains("jane@example.com") == false)
    }

    @Test func keepsEntriesUnredactedWhenAsked() async {
        let hub = DeviceHub(redactor: nil)
        await hub.connect(sending: [Wire.entry("Signed in jane@example.com")])
        #expect(await hub.search(LogQuery()).entries[0].entry.message == "Signed in jane@example.com")
    }

    @Test func ignoresAppsOutsideTheAllowlist() async {
        let hub = DeviceHub(allowedApps: ["com.acme.shop"])
        await hub.connect("com.other.app", sending: [Wire.entry("hidden")])
        await hub.connect("com.acme.shop (2)", sending: [Wire.entry("visible")])
        #expect(await hub.devicesSummary().map(\.device) == ["com.acme.shop (2)"])
        #expect(await hub.search(LogQuery()).entries.map(\.entry.message) == ["visible"])
    }

    @Test func reportsDeviceStatesAndHello() async {
        let hub = DeviceHub()
        await hub.connect(sending: [Wire.entry("hi")])
        var device = await hub.devicesSummary()[0]
        #expect(device.state == .connected)
        #expect(device.protocolVersion == 2)
        #expect(device.appVersion == "1.4.2")
        #expect(device.buffered == 1)

        await hub.handle(.disconnected(device: "com.acme.shop"))
        device = await hub.devicesSummary()[0]
        #expect(device.state == .reconnecting)
        await hub.handle(.gone(device: "com.acme.shop"))
        device = await hub.devicesSummary()[0]
        #expect(device.state == .gone)
        #expect(device.buffered == 1, "history survives a disconnect")
    }

    @Test func returnsAnEntryWithItsNeighbours() async throws {
        let hub = DeviceHub()
        let entries = (1...7).map { Wire.entry("entry \($0)") }
        await hub.connect(sending: entries)
        let found = try #require(await hub.entry(id: entries[3].id, context: 2))
        #expect(found.entry.entry.message == "entry 4")
        #expect(found.before.map(\.entry.message) == ["entry 2", "entry 3"])
        #expect(found.after.map(\.entry.message) == ["entry 5", "entry 6"])
    }

    @Test func reconstructsNetworkRequests() async {
        let hub = DeviceHub(redactor: nil)
        await hub.connect(sending: [
            Wire.entry("HTTP request", metadata: ["http.method": "POST", "http.url": "https://api.acme.com/checkout"]),
            Wire.entry("HTTP response", level: .warning, metadata: [
                "http.method": "POST", "http.url": "https://api.acme.com/checkout",
                "http.status": 402, "http.duration_ms": 123.4, "http.response_bytes": 88
            ]),
            Wire.entry("HTTP response", metadata: ["http.method": "GET", "http.url": "https://api.acme.com/cart", "http.status": 200]),
            Wire.entry("HTTP failure", level: .error, metadata: ["http.method": "GET", "http.url": "https://api.acme.com/x", "error": "offline"])
        ])
        let all = await hub.networkRequests()
        #expect(all.count == 3)
        let failed = await hub.networkRequests(failedOnly: true)
        #expect(failed.map(\.url) == ["https://api.acme.com/checkout", "https://api.acme.com/x"])
        #expect(failed[0].status == 402)
        #expect(failed[0].durationMS == 123.4)
        #expect(failed[1].error == "offline")
    }

    @Test func waitForResolvesOnTheNextMatchingEntry() async {
        let hub = DeviceHub()
        await hub.connect(sending: [Wire.entry("old error", level: .error)])
        async let match = hub.waitFor(LogQuery(minLevel: .error), timeout: .seconds(5))
        try? await Task.sleep(for: .milliseconds(100))
        await hub.send(Wire.entry("info", level: .info))
        await hub.send(Wire.entry("checkout failed", level: .error))
        #expect(await match?.entry.message == "checkout failed")
    }

    @Test func waitForTimesOut() async {
        let hub = DeviceHub()
        await hub.connect()
        let match = await hub.waitFor(LogQuery(text: "never"), timeout: .milliseconds(100))
        #expect(match == nil)
    }
}
