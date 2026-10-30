#if canImport(UIKit)
import UIKit
import WebKit

/// Display-text wireframes with explicit privacy controls. Never reads input values or pixels.
@MainActor public final class NativeReplay {
    private weak var window: UIWindow?
    private var timer: Timer?
    private var frames = [[String: Any]]()
    private var started: TimeInterval = 0
    private let session = UUID().uuidString
    private let submit: ([String: Any]) -> Void
    private let blocked: NSHashTable<UIView> = .weakObjects()
    private let publicText = NSMapTable<UIView, NSString>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private let maskedText: NSHashTable<UIView> = .weakObjects()
    private let maskAllText: Bool
    private let maxDuration: TimeInterval
    internal private(set) var limitReached = false
    internal var sessionID: String { session.replacingOccurrences(of:"-",with:"").lowercased() }
    private let origin = Date().timeIntervalSince1970 * 1000
    private let uptime: TimeInterval
    private let clock: () -> TimeInterval
    private var batchStart: Double = 0
    private var inactiveObserver: NSObjectProtocol?

    internal init(window: UIWindow, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, maskAllText: Bool = false, maxDuration: TimeInterval = 900, submit: @escaping ([String: Any]) -> Void) {
        self.window = window; self.submit = submit; self.clock = clock; self.uptime = clock(); self.maskAllText = maskAllText; self.maxDuration = maxDuration
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
    public func unblock(_ view: UIView) { blocked.remove(view) }
    /// Supply a reviewed, static public message, never a customer's actual text.
    /// Only UILabel/UIButton support this. Blocked ancestors always take precedence.
    public func allowPublicText(_ view: UIView, text: String) {
        guard view is UILabel || view is UIButton else { return }
        let bounded = text.unicodeScalars.prefix(160).map { String($0) }.joined()
        publicText.setObject(bounded as NSString, forKey: view)
    }
    public func maskText(_ view: UIView) { maskedText.add(view); publicText.removeObject(forKey: view) }
    public func unmaskText(_ view: UIView) { maskedText.remove(view) }
    internal func isRecording(in window: UIWindow) -> Bool { timer != nil && self.window === window }
    private func hex(_ color: UIColor?, traits: UITraitCollection) -> String? {
        guard let color = color?.resolvedColor(with: traits) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.95 else { return nil }
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
    private func capture() {
        guard !limitReached else { return }
        if clock()-uptime >= maxDuration { stopAtLimit(); return }
        guard let window = window else { stop(); return }
        guard UIApplication.shared.applicationState == .active, !window.isHidden,
              window.isKeyWindow, !window.screen.isCaptured else { flush(); return }
        captureFrame(in: window)
    }
    internal func captureFrame(in window: UIWindow) {
        guard !limitReached else { return }
        if clock()-uptime >= maxDuration { stopAtLimit(); return }
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.width <= 10000, bounds.height <= 10000 else { return }
        var nodes = [[String: Any]]()
        var publicBytes = 0
        var masks = [CGRect]()
        var scanned = 0
        var depthExceeded = false
        var hasFramework = false
        func scan(_ view: UIView, depth: Int, clip: CGRect) {
            if depth>64 { depthExceeded=true; return }
            scanned += 1
            guard scanned <= 4096, depth <= 64, !view.isHidden, view.alpha > 0 else { return }
            let rect = view.convert(view.bounds,to:window).intersection(clip).intersection(bounds)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
            if view is ReplayAnchorView { hasFramework = true }
            if blocked.contains(view) || maskedText.contains(view) || view is UITextField || view is UITextView || view is WKWebView || (view as? ReplayAnchorView)?.masked == true {
                masks.append(rect); return
            }
            for child in view.subviews { scan(child,depth:depth+1,clip:view.clipsToBounds ? rect : clip); if scanned>4096 { break } }
        }
        scan(window,depth:0,clip:bounds)
        let incomplete = depthExceeded || scanned>4096
        func hidden(_ rect: CGRect) -> Bool { incomplete || masks.contains { $0.intersects(rect) } }
        func visit(_ view: UIView, depth: Int, clip: CGRect) {
            guard depth <= 32, nodes.count < 256, !view.isHidden, view.alpha > 0 else { return }
            let rect = view.convert(view.bounds, to: window).intersection(clip).intersection(bounds)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
            let privateView = blocked.contains(view) || view is WKWebView
            let anchor = view as? ReplayAnchorView
            // A non-masking privacy anchor is not a visual element.
            if let anchor = anchor, anchor.kind == nil && !anchor.masked { return }
            let input = view is UITextField || view is UITextView
            let textView = view is UILabel || view is UIButton || anchor?.kind != nil
            let textHidden = textView && hidden(rect)
            let kind = privateView || anchor?.masked == true ? "private" : input ? "input" : textHidden ? "private" : anchor?.kind ?? (view is UIButton ? "button" : view is UILabel ? "text" : view is UIImageView ? "image" : "view")
            var node: [String: Any] = ["x": rect.minX - bounds.minX, "y": rect.minY - bounds.minY, "width": rect.width, "height": rect.height, "kind": kind]
            if !privateView && !input && !textHidden && anchor?.masked != true {
                node["background"] = hex(anchor?.replayBackground ?? view.backgroundColor, traits: view.traitCollection)
                if kind == "text" || kind == "button" {
                    let label = (view as? UILabel) ?? (view as? UIButton)?.titleLabel
                    // Mask checks precede actual display-text access. Never read accessibility/input values.
                    let actual = maskAllText ? nil : (anchor?.displayText ?? (view as? UILabel)?.text ?? (view as? UIButton)?.currentTitle)
                    if let value = publicText.object(forKey:view).map({ $0 as String }) ?? actual {
                        let bounded = value.unicodeScalars.prefix(160).map { String($0) }.joined()
                        let bytes = (try? JSONSerialization.data(withJSONObject: [bounded]).count) ?? 4097
                        if publicBytes+bytes <= 4096 { node["text"]=bounded; publicBytes += bytes }
                    }
                    node["foreground"] = hex(anchor?.replayForeground ?? label?.textColor, traits: view.traitCollection)
                    node["font_size"] = min(48, max(8, anchor?.replayFontSize ?? label?.font.pointSize ?? 14))
                }
            }
            nodes.append(node)
            if privateView || kind != "view" { return }
            for child in view.subviews.prefix(256) { visit(child, depth: depth + 1, clip: view.clipsToBounds ? rect : clip) }
        }
        if incomplete { nodes = [["x":0,"y":0,"width":bounds.width,"height":bounds.height,"kind":"private"]] }
        else { visit(window, depth: 0, clip: bounds) }
        let now = clock()
        let data: [String: Any] = ["version": 3, "text_mode": maskAllText || incomplete ? "masked" : "visible", "framework":hasFramework ? "mixed" : "uikit", "platform": "ios", "session_id": session,
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
        let duration = min(max(0,(uptime+maxDuration-started)*1000),min(60000, max(1000, min(last+1000, (clock()-started)*1000))))
        submit(["session_id": session.replacingOccurrences(of: "-", with: "").lowercased(),
                "batch_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                "batch_started_at": batchStart, "batch_ended_at": batchStart+duration,
                "duration_ms": duration, "events": frames])
        frames.removeAll()
    }
    internal func stopAtLimit(discard: Bool = false) { limitReached=true; stop(discard:discard) }

    internal func stop(discard: Bool = false) {
        timer?.invalidate(); timer = nil
        if let inactiveObserver = inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver); self.inactiveObserver = nil }
        if discard { frames.removeAll() } else { flush() }
    }
}

/// A supported SwiftUI UIViewRepresentable bridge. No private SwiftUI hierarchy APIs.
@MainActor internal final class ReplayAnchorView: UIView {
    var kind: String?
    var displayText: String?
    var masked = false
    var replayBackground: UIColor?
    var replayForeground: UIColor?
    var replayFontSize: CGFloat = 14
}
#endif
