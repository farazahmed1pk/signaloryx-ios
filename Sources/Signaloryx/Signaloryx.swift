import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

public struct SignaloryxOptions {
    public let dsn: String
    public let baseURL: URL
    public var environment = "production"
    public var release: String?
    public var maxQueueSize = 100
    /// Applies to errors, logs and transactions before storage/network. Return nil to discard.
    public var beforeSend: ([String: Any]) -> [String: Any]? = { $0 }
    public init(dsn: String, baseURL: URL = URL(string: "https://www.signaloryx.com")!) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, ["", "/"].contains(baseURL.path),
              dsn.range(of: "^[a-zA-Z0-9-]{1,128}$", options: .regularExpression) != nil else { throw SignaloryxError.invalidConfiguration }
        self.dsn = dsn; self.baseURL = baseURL
    }
}
public enum SignaloryxError: Error { case invalidConfiguration, invalidDuration }

/// Explicit handled-error instrumentation with optional content-free UIKit wireframes.
public final class Signaloryx {
    internal struct Item: Codable {
        let id: UUID
        let kind: String
        let created: Date
        let payload: Data
        var attempts: Int
    }
    internal typealias Transport = (URLRequest, @escaping (Int, TimeInterval) -> Void) -> Void
    private let options: SignaloryxOptions
    private let worker = DispatchQueue(label: "com.signaloryx.sdk")
    private var timer: DispatchSourceTimer?
    private var items = [Item]()
    private var breadcrumbs = [[String: Any]]()
    private var tags = [String: String]()
    private var userID: String?
    private var enabled = true
    private var closed = false
    private var sending = false
    private var nextAttempt = Date.distantPast
    private var dropped = 0
    private let storage: URL?
    private let transport: Transport
    private let session: URLSession?
    private let replayPermissionLock = NSLock()
    private var replayAllowed = true
    private var replayClosed = false
    #if canImport(UIKit)
    @MainActor private var replayRecorder: NativeReplay?
    /// Start after consent on the main thread. Each call samples once; keep the returned recorder to block subtrees.
    @MainActor public func startReplay(in window: UIWindow, consentGranted: Bool, sampleRate: Double = 0.1) -> NativeReplay? {
        replayRecorder?.stop(discard: !consentGranted); replayRecorder = nil
        guard sampleRate.isFinite, (0...1).contains(sampleRate), consentGranted, sampleRate > 0,
              Double.random(in: 0..<1) < sampleRate else { return nil }
        replayPermissionLock.lock()
        let canRecord = replayAllowed
        replayPermissionLock.unlock()
        guard canRecord else { return nil }
        let recorder = NativeReplay(window: window) { [weak self] payload in self?.captureReplayBatch(payload) }
        replayRecorder = recorder
        return recorder
    }
    @MainActor public func stopReplay() { replayRecorder?.stop(); replayRecorder = nil }
    private func discardReplay() { DispatchQueue.main.async { self.replayRecorder?.stop(discard: true); self.replayRecorder = nil } }
    #else
    private func discardReplay() {}
    #endif
    internal func captureReplayBatch(_ payload: [String: Any]) {
        worker.async {
            var value = payload; value["environment"] = self.options.environment
            self.enqueue("replay", payload: value)
        }
    }

    public convenience init(options: SignaloryxOptions) throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Signaloryx", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryURL = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directoryURL.setResourceValues(values)
        let key = SHA256.hash(data: Data((options.baseURL.absoluteString + "/" + options.dsn).utf8)).map { String(format: "%02x", $0) }.joined()
        try self.init(options: options, storage: directory.appendingPathComponent(key + ".json"), session: session) { request, completion in
            session.dataTask(with: request) { data, response, _ in
                let http = response as? HTTPURLResponse
                let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let dropped = body?["status"] as? String == "dropped"
                completion(dropped ? 402 : http?.statusCode ?? 0, TimeInterval(http?.value(forHTTPHeaderField: "Retry-After") ?? "0") ?? 0)
            }.resume()
        }
    }

    internal init(options: SignaloryxOptions, storage: URL?, session: URLSession? = nil, transport: @escaping Transport) throws {
        guard (1...1000).contains(options.maxQueueSize) else { throw SignaloryxError.invalidConfiguration }
        self.options = options; self.storage = storage; self.transport = transport; self.session = session
        if let storage = storage, let data = try? Data(contentsOf: storage), data.count <= 70_000_000,
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = Array(saved.filter { Date().timeIntervalSince($0.created) < 86400 && $0.payload.count <= 65536 && ["event", "log", "transaction", "replay"].contains($0.kind) }.prefix(options.maxQueueSize))
        }
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.drain() }
        self.timer = timer; timer.resume()
    }
    deinit { timer?.cancel(); session?.invalidateAndCancel() }

    public func setTags(_ value: [String: String]) { worker.async { self.tags = value.prefix(50).reduce(into: [:]) { $0[String($1.key.prefix(100))] = String($1.value.prefix(500)) } } }
    public func setUser(id: String?) { worker.async { self.userID = id.map { String($0.prefix(256)) } } }
    public func addBreadcrumb(_ message: String, category: String = "app") {
        worker.async {
            guard self.enabled && !self.closed else { return }
            self.breadcrumbs.append(["message": String(message.prefix(1000)), "category": String(category.prefix(100)), "timestamp": Date().timeIntervalSince1970])
            if self.breadcrumbs.count > 50 { self.breadcrumbs.removeFirst() }
        }
    }
    public func capture(error: Error) { captureMessage(String(describing: error), level: "error", errorType: String(reflecting: type(of: error))) }
    public func captureMessage(_ message: String, level: String = "info", errorType: String = "Message") {
        guard ["error", "warning", "info"].contains(level) else { return }
        worker.async {
            var payload: [String: Any] = ["message": String(message.prefix(8000)), "error_type": errorType, "level": level, "platform": "ios", "environment": self.options.environment, "tags": self.tags, "breadcrumbs": self.breadcrumbs]
            if let release = self.options.release { payload["release"] = release }
            if let id = self.userID { payload["user"] = ["id": id] }
            self.enqueue("event", payload: payload)
        }
    }
    public func captureLog(_ message: String, level: String = "info", attributes: [String: String] = [:]) {
        worker.async { self.enqueue("log", payload: ["message": String(message.prefix(8000)), "level": level, "attributes": attributes]) }
    }
    public func captureTransaction(name: String, durationMs: Double, op: String = "mobile.task", status: String = "ok") throws {
        guard durationMs.isFinite && durationMs >= 0 else { throw SignaloryxError.invalidDuration }
        worker.async { self.enqueue("transaction", payload: ["name": String(name.prefix(1000)), "duration_ms": durationMs, "op": op, "status": status, "environment": self.options.environment]) }
    }
    private func enqueue(_ kind: String, payload: [String: Any]) {
        guard enabled && !closed, let filtered = options.beforeSend(payload), JSONSerialization.isValidJSONObject(filtered),
              let data = try? JSONSerialization.data(withJSONObject: filtered), data.count <= 65536 else { return }
        if items.count == options.maxQueueSize { items.removeFirst(); dropped += 1 }
        items.append(Item(id: UUID(), kind: kind, created: Date(), payload: data, attempts: 0)); persist()
    }
    /// Completion runs on the SDK queue after this attempt, not a delivery guarantee. Do not block it.
    public func flush(completion: (() -> Void)? = nil) { worker.async { self.drain(completion: completion) } }
    public func statistics(completion: @escaping (Int, Int) -> Void) { worker.async { completion(self.items.count, self.dropped) } }
    /// Purges stored payloads and scope. Requests already sent cannot be recalled.
    public func setEnabled(_ value: Bool) {
        replayPermissionLock.lock(); replayAllowed = value && !replayClosed; replayPermissionLock.unlock()
        worker.async { self.enabled = value; if !value { self.items.removeAll(); self.breadcrumbs.removeAll(); self.tags.removeAll(); self.userID = nil; self.persist() } }
        if !value { discardReplay() }
    }
    public func close() {
        replayPermissionLock.lock(); replayClosed = true; replayAllowed = false; replayPermissionLock.unlock()
        discardReplay(); worker.async { self.closed = true; self.timer?.cancel(); self.persist(); self.session?.invalidateAndCancel() }
    }
    private func persist() {
        guard let storage = storage, let data = try? JSONEncoder().encode(items) else { return }
        #if os(iOS)
        try? data.write(to: storage, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: storage, options: .atomic)
        #endif
    }
    private func drain(completion: (() -> Void)? = nil) {
        guard enabled && !closed && !sending && Date() >= nextAttempt && !items.isEmpty else { completion?(); return }
        let item = items[0]
        if Date().timeIntervalSince(item.created) >= 86400 { items.removeFirst(); dropped += 1; persist(); drain(completion: completion); return }
        let url = options.baseURL.appendingPathComponent("api/ingest/\(options.dsn)/\(item.kind)")
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = item.payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sending = true
        transport(request) { [weak self] status, retryAfter in
            guard let self = self else { completion?(); return }
            self.worker.async {
                self.sending = false
                guard self.items.first?.id == item.id else { completion?(); return }
                let retry = status == 0 || status == 408 || status == 429 || status >= 500
                let attempts = item.attempts + 1
                if retry && attempts < 5 {
                    self.items[0].attempts = attempts
                    self.nextAttempt = Date().addingTimeInterval(max(pow(2, Double(attempts)), min(max(retryAfter, 0), 3600)))
                    self.persist(); completion?(); return
                }
                self.items.removeFirst(); if !(200...299).contains(status) { self.dropped += 1 }
                self.persist(); self.drain(completion: completion)
            }
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
