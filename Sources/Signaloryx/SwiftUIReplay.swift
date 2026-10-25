#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// A normal SwiftUI Text with a supported replay geometry/text bridge.
/// Display text is visible by default; use signaloryxReplayMask on sensitive content.
@available(iOS 14.0, *)
public struct SignaloryxReplayText: View {
    private let text: String
    private let fontSize: CGFloat
    private let foreground: Color
    public init(_ text: String, fontSize: CGFloat = 14, foreground: Color = .primary) {
        self.text=text; self.fontSize=fontSize; self.foreground=foreground
    }
    public var body: some View {
        Text(text).font(.system(size:fontSize)).foregroundColor(foreground)
            .signaloryxReplayText(text,fontSize:fontSize,foreground:foreground)
    }
}

@available(iOS 14.0, *)
private struct ReplayBridge: UIViewRepresentable {
    let text: String?
    let masked: Bool
    let button: Bool
    let fontSize: CGFloat
    let foreground: Color
    func makeUIView(context: Context) -> ReplayAnchorView {
        let view=ReplayAnchorView()
        view.isUserInteractionEnabled=false; view.isAccessibilityElement=false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: ReplayAnchorView, context: Context) {
        view.kind = text == nil ? nil : (button ? "button" : "text")
        view.displayText=text; view.masked=masked
        view.replayForeground=UIColor(foreground)
        view.replayFontSize=fontSize.isFinite ? min(48,max(8,fontSize)) : 14
    }
    static func dismantleUIView(_ view: ReplayAnchorView, coordinator: ()) {
        view.displayText=nil; view.kind=nil; view.masked=false
    }
}

@available(iOS 14.0, *)
public extension View {
    /// Attach to existing Text/Button wrappers; pass their display string, never editable values.
    func signaloryxReplayText(_ text: String, button: Bool = false,
                             fontSize: CGFloat = 14, foreground: Color = .primary) -> some View {
        background(ReplayBridge(text:text,masked:false,button:button,fontSize:fontSize,foreground:foreground))
    }
    /// Masks the rendered bounds, including SDK bridges and embedded UIKit children.
    /// Apply before the first sample; toggle false only when the content may be captured.
    func signaloryxReplayMask(_ masked: Bool = true) -> some View {
        background(ReplayBridge(text:nil,masked:masked,button:false,fontSize:14,foreground:.primary))
    }
}
#endif
