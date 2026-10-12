import XCTest
@testable import Signaloryx

final class SignaloryxTests: XCTestCase {
    private func flush(_ client: Signaloryx) { let done = expectation(description: "flush"); client.flush { done.fulfill() }; wait(for: [done], timeout: 5) }
    private func count(_ client: Signaloryx) -> Int {
        var count = -1; let done = expectation(description: "statistics")
        client.statistics { value, _ in count = value; done.fulfill() }; wait(for: [done], timeout: 5); return count
    }
    func testConfigurationRejectsUnsafeOrigins() {
        for origin in ["http://example.com", "https://user:secret@example.com", "https://example.com/path", "https://example.com?token=x"] { XCTAssertThrowsError(try SignaloryxOptions(dsn: "fixture", baseURL: URL(string: origin)!)) }
        XCTAssertThrowsError(try SignaloryxOptions(dsn: "../other"))
    }
    func testBackendPayloadsAndAcknowledgement() throws {
        var options = try SignaloryxOptions(dsn: "fixture"); options.release = "1.2.3"
        var sent = [String: Any]()
        let client = try Signaloryx(options: options, storage: nil) { request, completion in
            let kind = request.url!.lastPathComponent
            XCTAssertEqual(request.url!.host, "www.signaloryx.com"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            sent[kind] = try! JSONSerialization.jsonObject(with: request.httpBody!); completion(200, 0)
        }
        defer { client.close() }
        client.setTags(["screen": "checkout"]); client.setUser(id: "opaque-42"); client.addBreadcrumb("Checkout opened")
        client.captureMessage("Checkout unavailable", level: "error"); client.captureLog("Handled failure"); try client.captureTransaction(name: "checkout", durationMs: 42)
        XCTAssertEqual(count(client), 3); flush(client); XCTAssertEqual(count(client), 0)
        let event = sent["event"] as! [String: Any]; XCTAssertEqual(event["platform"] as? String, "ios"); XCTAssertEqual((event["user"] as? [String: String])?["id"], "opaque-42")
        if let path = ProcessInfo.processInfo.environment["SDK_CONTRACT_OUTPUT"] { try JSONSerialization.data(withJSONObject: sent).write(to: URL(fileURLWithPath: path)) }
    }
    func testOfflinePersistenceAndReopening() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let options = try SignaloryxOptions(dsn: "fixture")
        let client = try Signaloryx(options: options, storage: file) { _, done in done(0, 0) }
        client.captureMessage("offline"); flush(client); XCTAssertEqual(count(client), 1); client.close()
        _ = count(client) // serialize close/persistence before reopening
        let reopened = try Signaloryx(options: options, storage: file) { _, done in done(201, 0) }; defer { reopened.close() }
        XCTAssertEqual(count(reopened), 1); flush(reopened); XCTAssertEqual(count(reopened), 0)
    }
    func testRetryAfterRetainsQueueAndValidationFailureDrops() throws {
        let client = try Signaloryx(options: SignaloryxOptions(dsn: "fixture"), storage: nil) { _, done in done(429, 60) }; defer { client.close() }
        client.captureMessage("limited"); flush(client); XCTAssertEqual(count(client), 1); flush(client); XCTAssertEqual(count(client), 1)
        let invalid = try Signaloryx(options: SignaloryxOptions(dsn: "fixture"), storage: nil) { _, done in done(422, 0) }; defer { invalid.close() }
        invalid.captureMessage("invalid"); flush(invalid); XCTAssertEqual(count(invalid), 0)
    }
    func testCapacityPrivacyAndOptOut() throws {
        var options = try SignaloryxOptions(dsn: "fixture"); options.maxQueueSize = 2
        options.beforeSend = { payload in var filtered = payload; filtered["message"] = "redacted"; return filtered }
        var messages = [String]()
        let client = try Signaloryx(options: options, storage: nil) { request, done in messages.append((try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])["message"] as! String); done(200, 0) }; defer { client.close() }
        for _ in 0..<3 { client.captureMessage("sensitive") }; XCTAssertEqual(count(client), 2); flush(client); XCTAssertEqual(messages, ["redacted", "redacted"])
        client.captureMessage("queued"); client.setEnabled(false); client.captureMessage("disabled"); XCTAssertEqual(count(client), 0)
    }
    func testInvalidPayloadDurationAndCorruptStorage() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try Data("invalid".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let client = try Signaloryx(options: SignaloryxOptions(dsn: "fixture"), storage: file) { _, _ in XCTFail("Should not send") }; defer { client.close() }
        client.captureLog("large", attributes: ["large": String(repeating: "x", count: 70000)])
        XCTAssertThrowsError(try client.captureTransaction(name: "task", durationMs: .nan)); XCTAssertEqual(count(client), 0)
    }
    func testExpiredQueueDoesNotTransmit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: file) }
        let item = Signaloryx.Item(id: UUID(), kind: "event", created: Date(timeIntervalSinceNow: -86401), payload: Data("{}".utf8), attempts: 0)
        try JSONEncoder().encode([item]).write(to: file)
        let client = try Signaloryx(options: SignaloryxOptions(dsn: "fixture"), storage: file) { _, _ in XCTFail("Expired record sent") }; defer { client.close() }; XCTAssertEqual(count(client), 0)
    }
}
