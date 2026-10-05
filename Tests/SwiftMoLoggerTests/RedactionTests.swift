import XCTest
@testable import SwiftMoLogger

final class RedactionTests: XCTestCase {

    func testEmailIsRedacted() {
        let redactor = Redactor()
        let (output, hits) = redactor.redact("user mohammed@example.com signed in")
        XCTAssertTrue(output.contains("[EMAIL]"))
        XCTAssertFalse(output.contains("mohammed@example.com"))
        XCTAssertTrue(hits.contains("email"))
    }

    func testBearerTokenIsRedacted() {
        let redactor = Redactor()
        let (output, _) = redactor.redact("Authorization: Bearer abc.def.ghi-token")
        XCTAssertTrue(output.contains("[TOKEN]"))
        XCTAssertFalse(output.contains("abc.def.ghi-token"))
    }

    func testJWTIsRedacted() {
        let redactor = Redactor()
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature"
        let (output, _) = redactor.redact("token=\(jwt) cached")
        XCTAssertTrue(output.contains("[JWT]"))
        XCTAssertFalse(output.contains(jwt))
    }

    func testCreditCardIsRedacted() {
        let redactor = Redactor()
        let (output, _) = redactor.redact("paid with 4111 1111 1111 1111 on file")
        XCTAssertTrue(output.contains("[CARD]"))
    }

    func testPhoneNumbersAreRedacted() {
        let redactor = Redactor()
        for text in ["call +1 415 555 0100", "call 415-555-0100 now", "phone=4155550100"] {
            XCTAssertTrue(redactor.redact(text).output.contains("[PHONE]"), text)
        }
    }

    func testDigitsInsideHexIDsAreNotPhoneNumbers() {
        let redactor = Redactor()
        // Real-looking trace / span IDs with long digit runs.
        let ids = ["4bf92f3577b34da6a3ce929d0e0e4736", "00f067aa0ba902b7", "a1234567890123bc", "deadbeef4155550100cafe"]
        for id in ids {
            XCTAssertEqual(redactor.redact("trace.id=\(id)").output, "trace.id=\(id)", id)
        }
    }

    func testCustomRulesAreApplied() throws {
        var redactor = Redactor(rules: [])
        try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#, replacement: "[SSN]"))
        let (output, hits) = redactor.redact("SSN: 123-45-6789 done")
        XCTAssertTrue(output.contains("[SSN]"))
        XCTAssertEqual(hits, ["ssn"])
    }

    func testMetadataValuesAreRedacted() {
        let redactor = Redactor()
        let metadata: LogMetadata = [
            "user_email": "a@b.com",
            "count": 42,
            "details": ["nested": .string("Bearer abc123")]
        ]
        let redacted = redactor.redact(metadata)
        XCTAssertEqual(redacted["user_email"], .string("[EMAIL]"))
        XCTAssertEqual(redacted["count"], .int(42))
        if case .dictionary(let inner) = redacted["details"] {
            XCTAssertTrue(inner["nested"]?.description.contains("[TOKEN]") ?? false)
        } else {
            XCTFail("nested metadata not preserved as dictionary")
        }
    }

    func testRedactingEngineWrapsAnotherEngine() {
        SwiftMoLogger.reset()
        let memory = MemoryLogEngine()
        SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: memory))
        SwiftMoLogger.info("contact me at admin@corp.com")
        let captured = memory.snapshot()
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].message.contains("[EMAIL]"))
    }
}
