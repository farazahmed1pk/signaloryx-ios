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
    @MainActor func testServerLimitStopsMatchingRecorderAndStillDeliversLogs() async throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=UIViewController();window.isHidden=false
        defer { window.isHidden=true }
        let log=expectation(description:"logs remain independent")
        let done=expectation(description:"server stop applied")
        let client=try Signaloryx(options:SignaloryxOptions(dsn:"synthetic"),storage:nil) { request,completion in
            if request.url!.path.hasSuffix("/replay") { completion(410,0) }
            else { log.fulfill();completion(200,0) }
        }
        let active=client.startReplay(in:window,consentGranted:true,sampleRate:1)!
        client.captureReplayBatch(["session_id":active.sessionID,"duration_ms":0,"events":[]])
        client.captureLog("Synthetic diagnostic log")
        client.flush { DispatchQueue.main.async { XCTAssertTrue(active.limitReached);done.fulfill() } }
        await fulfillment(of:[log,done],timeout:5)
        XCTAssertNil(client.startReplay(in:window,consentGranted:true,sampleRate:1))
        client.setEnabled(false);client.close()
    }
    @MainActor func testDelayedServerLimitCannotStopNewRecording() async throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController=UIViewController();window.isHidden=false
        defer { window.isHidden=true }
        var reply:((Int,TimeInterval)->Void)?
        let requestSent=expectation(description:"old recording request in flight")
        let done=expectation(description:"old response reconciled")
        let client=try Signaloryx(options:SignaloryxOptions(dsn:"synthetic"),storage:nil) { _,completion in
            reply=completion;requestSent.fulfill()
        }
        let old=client.startReplay(in:window,consentGranted:true,sampleRate:1)!
        client.captureReplayBatch(["session_id":old.sessionID,"duration_ms":0,"events":[]])
        client.flush()
        await fulfillment(of:[requestSent],timeout:5)
        client.stopReplay()
        let current=client.startReplay(in:window,consentGranted:true,sampleRate:1)!
        reply!(410,0)
        client.flush { DispatchQueue.main.async { XCTAssertFalse(current.limitReached);done.fulfill() } }
        await fulfillment(of:[done],timeout:5)
        client.setEnabled(false);client.close()
    }
}
#endif
