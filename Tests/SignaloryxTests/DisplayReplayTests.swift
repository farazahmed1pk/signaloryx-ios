import XCTest
#if canImport(UIKit)
import UIKit
import SwiftUI
@testable import Signaloryx

final class DisplayReplayTests: XCTestCase {
    @MainActor private func json(_ payloads: [[String:Any]]) throws -> String {
        String(data:try JSONSerialization.data(withJSONObject:payloads),encoding:.utf8)!
    }
    @MainActor private func window() -> UIWindow {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=UIViewController(); window.rootViewController!.view.frame=window.bounds
        window.isHidden=false; return window
    }
    @MainActor func testDefaultDisplayTextAndReversibleMasks() throws {
        let window=window(); defer { window.isHidden=true }
        let label=UILabel(frame:CGRect(x:10,y:10,width:300,height:50)); label.text="Catalog ready"
        window.rootViewController!.view.addSubview(label)
        var payloads=[[String:Any]](); let recorder=NativeReplay(window:window) { payloads.append($0) }
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertTrue(try json(payloads).contains("Catalog ready")); payloads.removeAll()
        recorder.maskText(label); label.text="SECRET_CUSTOMER"
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertFalse(try json(payloads).contains("SECRET_")); payloads.removeAll()
        recorder.unmaskText(label); label.text="Public again"
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        XCTAssertTrue(try json(payloads).contains("Public again"))
    }
    @MainActor func testMaskAllAndSubtreeBlockOverride() throws {
        let window=window(); defer { window.isHidden=true }
        let parent=UIView(frame:CGRect(x:10,y:10,width:300,height:80))
        let label=UILabel(frame:parent.bounds); label.text="SECRET_CUSTOMER"; parent.addSubview(label)
        window.rootViewController!.view.addSubview(parent)
        var payloads=[[String:Any]](); let recorder=NativeReplay(window:window,maskAllText:true) { payloads.append($0) }
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertFalse(try json(payloads).contains("SECRET_")); payloads.removeAll()
        recorder.allowPublicText(label,text:"Public template")
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertTrue(try json(payloads).contains("Public template")); payloads.removeAll()
        recorder.block(parent)
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertFalse(try json(payloads).contains("Public template")); payloads.removeAll()
        recorder.unblock(parent)
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        XCTAssertTrue(try json(payloads).contains("Public template"))
    }
    @MainActor func testPrivacyTraversalLimitFailsClosed() throws {
        let window=window(); defer { window.isHidden=true }
        let label=UILabel(frame:CGRect(x:0,y:0,width:300,height:40)); label.text="SECRET_LIMIT"
        window.rootViewController!.view.addSubview(label)
        for _ in 0..<4100 { window.rootViewController!.view.addSubview(UIView(frame:CGRect(x:0,y:0,width:1,height:1))) }
        var payloads=[[String:Any]](); let recorder=NativeReplay(window:window) { payloads.append($0) }
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        XCTAssertFalse(try json(payloads).contains("SECRET_"))
        let events=payloads[0]["events"] as! [[String:Any]]
        XCTAssertEqual((events[0]["data"] as! [String:Any])["text_mode"] as? String,"masked")
    }
    @available(iOS 14.0, *)
    @MainActor private func host<Content: View>(_ content: Content) -> UIWindow {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        let controller=UIHostingController(rootView:content)
        window.rootViewController=controller; window.makeKeyAndVisible()
        controller.view.frame=window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        return window
    }
    @available(iOS 14.0, *)
    @MainActor func testRealSwiftUIHostedLabelsAndPrivateParent() throws {
        let window=host(VStack {
            SignaloryxReplayText("SwiftUI catalog ready",fontSize:20).frame(width:300,height:60)
            VStack {
                SignaloryxReplayText("SECRET_SWIFTUI_CUSTOMER")
                EmbeddedLabel()
            }.frame(width:300,height:120).signaloryxReplayMask()
            TextField("Email",text:.constant("SECRET_INPUT"))
            SecureField("Password",text:.constant("SECRET_PASSWORD"))
        }.padding())
        defer { window.isHidden=true }
        var payloads=[[String:Any]](); let recorder=NativeReplay(window:window) { payloads.append($0) }
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        let value=try json(payloads)
        XCTAssertTrue(value.contains("SwiftUI catalog ready")); XCTAssertFalse(value.contains("SECRET_"))
        let frame=(payloads[0]["events"] as! [[String:Any]])[0]["data"] as! [String:Any]
        XCTAssertEqual(frame["framework"] as? String,"mixed")
        print("SIGNALORYX_SWIFTUI_REPLAY_CONTRACT="+(try JSONSerialization.data(withJSONObject:payloads[0])).base64EncodedString())
    }
    @available(iOS 14.0, *)
    @MainActor func testSwiftUIRecompositionAndMaskToggle() throws {
        let model=ReplayModel()
        let window=host(ModelContent(model:model)); defer { window.isHidden=true }
        var payloads=[[String:Any]](); let recorder=NativeReplay(window:window) { payloads.append($0) }
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertFalse(try json(payloads).contains("SECRET_")); payloads.removeAll()
        model.text="Updated public label"; model.masked=false
        RunLoop.main.run(until:Date().addingTimeInterval(0.15)); window.layoutIfNeeded()
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        XCTAssertTrue(try json(payloads).contains("Updated public label")); XCTAssertFalse(try json(payloads).contains("SECRET_"))
    }
}
@available(iOS 14.0, *)
private final class ReplayModel: ObservableObject { @Published var text="SECRET_REUSED"; @Published var masked=true }
@available(iOS 14.0, *)
private struct ModelContent: View {
    @ObservedObject var model: ReplayModel
    var body: some View { SignaloryxReplayText(model.text).frame(width:300,height:60).signaloryxReplayMask(model.masked) }
}
@available(iOS 14.0, *)
private struct EmbeddedLabel: UIViewRepresentable {
    func makeUIView(context:Context) -> UILabel { let label=UILabel(); label.text="SECRET_EMBEDDED_UIKIT"; return label }
    func updateUIView(_ view:UILabel,context:Context) {}
}
#endif
