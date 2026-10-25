#if canImport(UIKit)
import UIKit
import WebKit

/// UIKit wireframes with explicitly supplied public labels. Never reads input values or pixels.
@MainActor public final class NativeReplay {
    private weak var window: UIWindow?
    private var timer: Timer?
    private var frames = [[String: Any]]()
    private var started: TimeInterval = 0
    private let session = UUID().uuidString
    private let submit: ([String: Any]) -> Void
    private let blocked: NSHashTable<UIView> = .weakObjects()
    private let publicText = NSMapTable<UIView, NSString>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private let origin = Date().timeIntervalSince1970 * 1000
    private let uptime: TimeInterval
    private let clock: () -> TimeInterval
    private var batchStart: Double = 0
    private var inactiveObserver: NSObjectProtocol?

    internal init(window: UIWindow, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, submit: @escaping ([String: Any]) -> Void) {
        self.window = window; self.submit = submit; self.clock = clock; self.uptime = clock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // Foundation Timer invokes this on the main run loop where it was created.
            MainActor.assumeIsolated { self?.capture() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        inactiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }
    deinit {
        timer?.invalidate()
        if let inactiveObserver = inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
    }
    /// Excludes a complete subtree; call before recording begins for sensitive content.
    public func block(_ view: UIView) { blocked.add(view) }
    /// Supply a reviewed, static public message, never a customer's actual text.
    /// Only UILabel/UIButton support this. Blocked ancestors always take precedence.
    public func allowPublicText(_ view: UIView, text: String) {
        guard view is UILabel || view is UIButton else { return }
        let bounded = text.unicodeScalars.prefix(160).map { String($0) }.joined()
        publicText.setObject(bounded as NSString, forKey: view)
    }
    public func maskText(_ view: UIView) { publicText.removeObject(forKey: view) }
    internal func isRecording(in window: UIWindow) -> Bool { timer != nil && self.window === window }
    private func hex(_ color: UIColor?, traits: UITraitCollection) -> String? {
        guard let color = color?.resolvedColor(with: traits) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.95 else { return nil }
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
    private func capture() {
        guard let window = window else { stop(); return }
        guard UIApplication.shared.applicationState == .active, !window.isHidden,
              window.isKeyWindow, !window.screen.isCaptured else { flush(); return }
        captureFrame(in: window)
    }
    internal func captureFrame(in window: UIWindow) {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.width <= 10000, bounds.height <= 10000 else { return }
        var nodes = [[String: Any]]()
        var publicBytes = 0
        func visit(_ view: UIView, depth: Int, clip: CGRect) {
            guard depth <= 32, nodes.count < 128, !view.isHidden, view.alpha > 0 else { return }
            let rect = view.convert(view.bounds, to: window).intersection(clip).intersection(bounds)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
            let privateView = blocked.contains(view) || view is WKWebView
            let kind = privateView ? "private" : view is UITextField || view is UITextView ? "input" : view is UIButton ? "button" : view is UILabel ? "text" : view is UIImageView ? "image" : "view"
            var node: [String: Any] = ["x": rect.minX - bounds.minX, "y": rect.minY - bounds.minY, "width": rect.width, "height": rect.height, "kind": kind]
            if !privateView {
                node["background"] = hex(view.backgroundColor, traits: view.traitCollection)
                if let approved = publicText.object(forKey: view), kind == "text" || kind == "button" {
                    let bytes = (try? JSONSerialization.data(withJSONObject: [approved]).count) ?? 4097
                    if publicBytes + bytes <= 4096 { node["text"] = approved as String; publicBytes += bytes }
                    let label = (view as? UILabel) ?? (view as? UIButton)?.titleLabel
                    node["foreground"] = hex(label?.textColor, traits: view.traitCollection)
                    node["font_size"] = min(48, max(8, label?.font.pointSize ?? 14))
                }
            }
            nodes.append(node)
            if privateView || kind != "view" { return }
            for child in view.subviews.prefix(128) { visit(child, depth: depth + 1, clip: view.clipsToBounds ? rect : clip) }
        }
        visit(window, depth: 0, clip: bounds)
        let now = clock()
        let data: [String: Any] = ["version": 2, "platform": "ios", "session_id": session,
                                  "width": bounds.width, "height": bounds.height, "nodes": nodes]
        let proposed: [String: Any] = ["type": "native_frame", "timestamp_ms": max(0, (now-started)*1000), "data": data]
        if !frames.isEmpty && (now-started > 55 || ((try? JSONSerialization.data(withJSONObject: frames + [proposed]).count) ?? 65536) > 50000) { flush() }
        if frames.isEmpty { started = now; batchStart = origin + (now-uptime)*1000 }
        frames.append(["type": "native_frame", "timestamp_ms": (now-started)*1000, "data": data])
        if frames.count == 5 { flush() }
    }
    private func flush() {
        guard !frames.isEmpty else { return }
        let last = frames.last?["timestamp_ms"] as? Double ?? 0
        // Suspension must not turn a stale frame into minutes of invented coverage.
        let duration = min(60000, max(1000, min(last+1000, (clock()-started)*1000)))
        submit(["session_id": session.replacingOccurrences(of: "-", with: "").lowercased(),
                "batch_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                "batch_started_at": batchStart, "batch_ended_at": batchStart+duration,
                "duration_ms": duration, "events": frames])
        frames.removeAll()
    }
    internal func stop(discard: Bool = false) {
        timer?.invalidate(); timer = nil
        if let inactiveObserver = inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver); self.inactiveObserver = nil }
        if discard { frames.removeAll() } else { flush() }
    }
}
#endif
