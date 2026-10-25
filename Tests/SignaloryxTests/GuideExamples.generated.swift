#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
import Signaloryx

@MainActor
final class ReplayCoordinator {
    private var telemetry: Signaloryx?
    private var recorder: NativeReplay?
    private weak var activeWindow: UIWindow?

    func begin(in window: UIWindow, consentGranted: Bool,
               privateViews: [UIView]) throws {
        guard consentGranted else { revoke(); return }
        if telemetry == nil {
            var options = try SignaloryxOptions(
                dsn: "YOUR_IOS_STAGING_DSN",
                baseURL: URL(string: "https://signaloryx.com")!)
            options.environment = "staging"
            options.replayMaskAllText = false // 0.4.0 default
            options.release = Bundle.main.infoDictionary?[
                "CFBundleShortVersionString"] as? String
            telemetry = try Signaloryx(options: options)
        }
        guard let telemetry = telemetry else { return }
        telemetry.setEnabled(true)
        if let previous = activeWindow, previous !== window {
            telemetry.stopReplay()
        }
        activeWindow = window
        recorder = telemetry.startReplay(in: window,
            consentGranted: true, sampleRate: 1.0) // staging QA
        privateViews.forEach { recorder?.block($0) }
    }
func publicLabel(_ label: UILabel, message: StaticString) {
    recorder?.allowPublicText(label,
        text: String(describing: message))
}
func publicButton(_ button: UIButton, message: StaticString) {
    recorder?.allowPublicText(button,
        text: String(describing: message))
}
func makePrivateAgain(_ view: UIView) {
    recorder?.maskText(view)
}
func endConsentedSession() {
    telemetry?.stopReplay() // queues a partial consented batch
    recorder = nil; activeWindow = nil
}
func revoke() {
    telemetry?.setEnabled(false) // discard frames AND queue first
    recorder = nil; activeWindow = nil
}
}
@MainActor final class MobileGuideIntegrationExamples: XCTestCase {
    func testConsentDeclineAndStaticPublicExamples() throws {
        let replay = ReplayCoordinator()
        let window = UIWindow(frame: CGRect(x: 0,y: 0,width: 390,height: 844))
        let customerDetailsContainer = UIView(), paymentContainer = UIView()
        let cartTitleLabel = UILabel(), errorMessageLabel = UILabel()
        let retryButton = UIButton()
        let consentAllowed = false // never construct/send telemetry in this fixture
// Retained coordinator + actual UIKit views owned by your app:
try replay.begin(in: window, consentGranted: consentAllowed,
    privateViews: [customerDetailsContainer, paymentContainer])
replay.publicLabel(cartTitleLabel, message: "Your shopping bag")
replay.publicButton(retryButton, message: "Try again")
// When creating the popup, before its next one-second sample:
replay.publicLabel(errorMessageLabel,
    message: "Unable to update your cart. Please try again.")
// Before reusing this label for customer-specific content:
replay.makePrivateAgain(errorMessageLabel)
// Consent withdrawal callback on the main actor:
replay.revoke()
    }
}
@available(iOS 14.0, *)
private struct FrameworkGuideExamples: View {
    let customerName = "Synthetic customer"
    let customerReference = "Synthetic private reference"
    @State private var email = ""
    var body: some View {

// Inside an approved, consented SwiftUI view:
VStack {
  SignaloryxReplayText("Your shopping bag", fontSize: 20)
  Text("Try again")
    .signaloryxReplayText("Try again", button: true)
  VStack {
    SignaloryxReplayText(customerName)
    TextField("Email", text: $email)
  }.signaloryxReplayMask()
}
// Toggle .signaloryxReplayMask(isPrivate) from app policy.
// Keep wrappers/modifiers on reused and asynchronous content.
    }
    var popup: some View {
// SwiftUI overlay inside the captured approved window:
VStack {
  SignaloryxReplayText(
    "Unable to update your cart. Please try again.")
  SignaloryxReplayText(customerReference)
    .signaloryxReplayMask()
}
    }
}
#endif
