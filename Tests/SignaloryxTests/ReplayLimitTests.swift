import XCTest
@testable import Signaloryx
#if canImport(UIKit)
import UIKit

final class ReplayLimitTests: XCTestCase {
    @MainActor func testBoundaryStopsAndDoesNotResumeAutomatically() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=UIViewController();window.isHidden=false
        defer { window.isHidden=true }
        var elapsed:TimeInterval=0
        var batches=[[String:Any]]()
        let recorder=NativeReplay(window:window,clock:{elapsed},maxDuration:60) { batches.append($0) }
        elapsed=59.9;recorder.captureFrame(in:window)
        elapsed=60;recorder.captureFrame(in:window)
        XCTAssertTrue(recorder.limitReached);XCTAssertEqual(batches.count,1)
        XCTAssertLessThanOrEqual(batches[0]["duration_ms"] as! Double,101)
        elapsed=120;recorder.captureFrame(in:window);XCTAssertEqual(batches.count,1)
        let client=try Signaloryx(options:SignaloryxOptions(dsn:"synthetic"),storage:nil) { _,completion in completion(200,0) }
        let active=client.startReplay(in:window,consentGranted:true,sampleRate:1)!
        active.stopAtLimit()
        XCTAssertNil(client.startReplay(in:window,consentGranted:true,sampleRate:1))
        client.stopReplay()
        XCTAssertNotNil(client.startReplay(in:window,consentGranted:true,sampleRate:1))
        client.setEnabled(false);client.close()
    }
    func testInvalidOptionsFailBeforeCollection() throws {
        let invalidValues:[Double] = [0,59,14401,.nan,.infinity]
        for invalid in invalidValues {
            var options=try SignaloryxOptions(dsn:"synthetic")
            options.replayMaxSessionDurationSeconds=invalid
            XCTAssertThrowsError(try Signaloryx(options:options,storage:nil) { _,completion in completion(200,0) })
        }
    }
}
#endif
