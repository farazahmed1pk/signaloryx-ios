#if canImport(UIKit)
import UIKit
import WebKit

/// Content-free UIKit wireframes. Does not capture pixels, text, accessibility labels or input values.
@MainActor public final class NativeReplay {
    private weak var window: UIWindow?
    private var timer: Timer?
    private var frames = [[String: Any]]()
    private var started: TimeInterval = 0
    private let session = UUID().uuidString
    private let submit: ([String: Any]) -> Void
    private let blocked: NSHashTable<UIView> = .weakObjects()

    internal init(window: UIWindow, submit: @escaping ([String: Any]) -> Void) {
        self.window = window; self.submit = submit
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Foundation Timer invokes this on the main run loop where it was created.
            MainActor.assumeIsolated { self?.capture() }
        }
    }
    deinit { timer?.invalidate() }
    /// Excludes a complete subtree; call before recording begins for sensitive content.
    public func block(_ view: UIView) { blocked.add(view) }
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
        func visit(_ view: UIView, depth: Int, clip: CGRect) {
            guard depth <= 32, nodes.count < 128, !view.isHidden, view.alpha > 0 else { return }
            let rect = view.convert(view.bounds, to: window).intersection(clip).intersection(bounds)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
            let privateView = blocked.contains(view) || view is WKWebView
            let kind = privateView ? "private" : view is UITextField || view is UITextView ? "input" : view is UIButton ? "button" : view is UILabel ? "text" : view is UIImageView ? "image" : "view"
            nodes.append(["x": rect.minX - bounds.minX, "y": rect.minY - bounds.minY, "width": rect.width, "height": rect.height, "kind": kind])
            if privateView || kind != "view" { return }
            for child in view.subviews.prefix(128) { visit(child, depth: depth + 1, clip: view.clipsToBounds ? rect : clip) }
        }
        visit(window, depth: 0, clip: bounds)
        let now = ProcessInfo.processInfo.systemUptime
        if !frames.isEmpty {
            let bytes = (try? JSONSerialization.data(withJSONObject: frames).count) ?? 65536
            if now - started > 60 || bytes > 35000 { flush() }
        }
        if frames.isEmpty { started = now }
        frames.append(["type": "native_frame", "timestamp_ms": (now - started) * 1000,
                       "data": ["version": 1, "platform": "ios", "session_id": session,
                                "width": bounds.width, "height": bounds.height, "nodes": nodes]])
        if frames.count == 5 { flush() }
    }
    private func flush() {
        guard !frames.isEmpty else { return }
        submit(["duration_ms": max(1000, frames.last?["timestamp_ms"] as? Double ?? 0), "events": frames])
        frames.removeAll()
    }
    internal func stop(discard: Bool = false) {
        timer?.invalidate(); timer = nil
        if discard { frames.removeAll() } else { flush() }
    }
}
#endif
