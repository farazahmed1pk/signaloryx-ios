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
        for _ in 0..<5 { recorder.captureFrame(in:window) }
        XCTAssertTrue(try json(payloads).contains("Updated public label")); XCTAssertFalse(try json(payloads).contains("SECRET_"))
        payloads.removeAll(); model.visible=false
        RunLoop.main.run(until:Date().addingTimeInterval(0.15)); window.layoutIfNeeded()
        for _ in 0..<5 { recorder.captureFrame(in:window) }; recorder.stop()
        XCTAssertFalse(try json(payloads).contains("Updated public label"))
    }
    @available(iOS 14.0, *)
    @MainActor func testScreenshotPreservesSwiftUIDesignAndMasksPrivatePixels() throws {
        let window=host(VStack(spacing:0) {
            Color.blue.frame(height:200)
            Color.red.frame(height:200).signaloryxReplayMask()
            TextField("Email",text:.constant("SECRET_INPUT")).signaloryxReplayMask()
            Color.green
        }.ignoresSafeArea())
        defer { window.isHidden=true }
        var payloads=[[String:Any]]()
        let recorder=NativeReplay(window:window,captureScreenshots:true) { payloads.append($0) }
        recorder.captureFrame(in:window); recorder.stop()
        let payload=try XCTUnwrap(payloads.first)
        let events=try XCTUnwrap(payload["events"] as? [[String:Any]])
        let frame=try XCTUnwrap(events.first?["data"] as? [String:Any])
        XCTAssertEqual(frame["version"] as? Int,4)
        XCTAssertGreaterThanOrEqual(frame["mask_count"] as? Int ?? 0,2)
        let encoded=try XCTUnwrap(frame["image_base64"] as? String)
        let bytes=try XCTUnwrap(Data(base64Encoded:encoded))
        XCTAssertLessThanOrEqual(bytes.count,44000)
        let image=try XCTUnwrap(UIImage(data:bytes)?.cgImage)
        let width=image.width, height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                                              space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        func pixel(_ pointY:CGFloat) -> ArraySlice<UInt8> {
            let offset=(Int(pointY/window.bounds.height*CGFloat(height))*width+width/2)*4
            return pixels[offset..<offset+3]
        }
        XCTAssertGreaterThan(Array(pixel(100))[2],200)
        XCTAssertTrue(pixel(300).allSatisfy { $0<20 })
        XCTAssertFalse(try json(payloads).contains("SECRET_INPUT"))
        print("SIGNALORYX_SCREENSHOT_REPLAY_CONTRACT="+(try JSONSerialization.data(withJSONObject:payload)).base64EncodedString())
    }
    @available(iOS 14.0, *)
    @MainActor func testScreenshotMaskAllFailsClosed() {
        let window=host(Color.red); defer { window.isHidden=true }
        var payloads=[[String:Any]]()
        let recorder=NativeReplay(window:window,maskAllText:true,captureScreenshots:true) { payloads.append($0) }
        recorder.captureFrame(in:window); recorder.stop()
        XCTAssertTrue(payloads.isEmpty)
    }
    @available(iOS 14.0, *)
    @MainActor func testScreenshotIntervalsAndDurationLimit() {
        let window=host(Color.blue); defer { window.isHidden=true }
        var now:TimeInterval=0
        var payloads=[[String:Any]]()
        let recorder=NativeReplay(window:window,clock:{now},maxDuration:60,captureScreenshots:true) { payloads.append($0) }
        recorder.captureFrame(in:window);XCTAssertTrue(payloads.isEmpty)
        now=1.1;recorder.captureFrame(in:window)
        XCTAssertEqual(payloads.first?["duration_ms"] as? Double ?? -1,1100,accuracy:1)
        now=2.2;recorder.captureFrame(in:window)
        XCTAssertEqual(payloads.last?["duration_ms"] as? Double ?? -1,1100,accuracy:1)
        now=60;recorder.captureFrame(in:window)
        XCTAssertTrue(recorder.limitReached)
        XCTAssertLessThanOrEqual(payloads.last?["duration_ms"] as? Double ?? .infinity,2000)
        let count=payloads.count;now=61;recorder.captureFrame(in:window)
        XCTAssertEqual(payloads.count,count)
    }
}
@available(iOS 14.0, *)
private final class ReplayModel: ObservableObject { @Published var text="SECRET_REUSED"; @Published var masked=true; @Published var visible=true }
@available(iOS 14.0, *)
private struct ModelContent: View {
    @ObservedObject var model: ReplayModel
    var body: some View { VStack { if model.visible { SignaloryxReplayText(model.text).frame(width:300,height:60).signaloryxReplayMask(model.masked) } } }
}
@available(iOS 14.0, *)
private struct EmbeddedLabel: UIViewRepresentable {
    func makeUIView(context:Context) -> UILabel { let label=UILabel(); label.text="SECRET_EMBEDDED_UIKIT"; return label }
    func updateUIView(_ view:UILabel,context:Context) {}
}
#endif
