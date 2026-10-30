# Signaloryx for iOS

## Unpublished 0.5.0 candidate: duration limits

```swift
var options = try SignaloryxOptions(dsn: "PROJECT_DSN")
options.replayMaxSessionDurationSeconds = 900 // 15 minutes; 60–14400
let client = try Signaloryx(options: options)
```

Monotonic elapsed time includes background gaps. Capture stops at the limit;
repeated starts do not restart it. Explicit stopReplay and a new consented start
begins a new recording. Server 410 stops its matching recorder and drops that
session's queued replay batches. Errors/logs remain independent. Lower tenant
duration/size limits win. Retain consent revoke and SwiftUI masking integration.
This requires rebuilding with 0.5.0 source; the published 0.4.0 package is unchanged.

## 0.4.0 preview: display text and SwiftUI

Use the official repository `https://github.com/farazahmed1pk/signaloryx-ios.git`
and pin the exact `0.4.0` SPM tag; add the Signaloryx product and rebuild your app.
Older 0.3.0 artifacts do not contain these APIs and remain unchanged.
The implementation below changes privacy defaults: UILabel/UIButton display text is
visible by default after consent. Inputs/passwords/WebViews remain protected. Mark
customer-detail text/subtrees before the first sample with `maskText` / `block`.
Use `unmaskText` / `unblock` only when content may be captured. Set
`options.replayMaskAllText = true` to retain mask-all behavior with explicit UIKit
public templates. Already-sent data cannot be recalled by changing a mask.

SwiftUI (iOS 14+) uses supported wrappers/modifiers, without inspecting private
SwiftUI internals:

```swift
import SwiftUI
import Signaloryx

VStack {
    SignaloryxReplayText("Your shopping bag", fontSize: 20)
    Text("Try again").signaloryxReplayText("Try again", button: true)
    VStack {
        SignaloryxReplayText(customerName)
        TextField("Email", text: $email)
    }.signaloryxReplayMask()
}
```

Use the Text wrapper in shared display components, or attach the text modifier with
that component's display string. Do not instrument editable values. A parent privacy
modifier masks intersecting framework and embedded UIKit text. Masks can be toggled;
composition updates change recorded text/bounds. Custom drawing, images, system and
separate-window popups remain outside this wireframe capture. The v3 API/player is
required for these v3 uploads. Physical-device app acceptance remains required.

The following installation material describes the published **0.3.0** release.

## Recording integration

SDK 0.3.0 preview offers opt-in UIKit wireframe capture, foreground-session timelines and explicitly approved static public label/button text. Follow the [session recording guidelines](https://signaloryx.com/docs/session-recording) and [native lifecycle reference](https://signaloryx.com/docs/mobile-integration). Start once per active scene on the main actor after consent, block private views, retain the recorder through ordinary background/foreground changes, and stop before account/window changes or sensitive workflows. Use `setEnabled(false)` to discard buffered and queued telemetry on opt-out. Test synthetic staging capture and physical-device overhead before production. SwiftUI internals, image pixels, unapproved/customer text, full video and automatic error-triggered recording are not supported.

Swift package for explicit errors, messages, breadcrumbs, logs and transactions. iOS 13+, Swift tools 5.9. Product: `Signaloryx`.

## Install with Swift Package Manager

Official SDK-only repository: `https://github.com/farazahmed1pk/signaloryx-ios.git`. Version `0.3.0` is the session-timeline preview; consult the [mobile integration guide](https://signaloryx.com/docs/mobile-integration) for publication status. In Xcode select **File → Add Package Dependencies**, enter that URL, select the published version and add the **Signaloryx** product to your app target. Do not use the private application repository.

Pin an exact reviewed release during the 0.x preview period. Commit `Package.resolved`. Updates are opt-in and require rebuilding, regression testing and releasing your app; dependency management does not hot-update installed applications.

```swift
import Signaloryx
var options = try SignaloryxOptions(dsn: "YOUR_PROJECT_DSN")
options.release = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
// Apply redaction/consent policy before queuing any telemetry.
let telemetry = try Signaloryx(options: options) // retain in your app service
telemetry.captureMessage("Synthetic test event", level: "warning")
telemetry.flush()
```

See the [integration guide](https://signaloryx.com/docs/mobile-integration) for redaction, queue limits, opt-out, offline tests and lifecycle limitations. No automatic fatal crashes or symbolication. UIKit wireframe replay is opt-in; see the native replay guide. Versioned downloads remain an offline alternative.

## Maintenance


Review CHANGELOG and migration notes, update the pinned version in a branch, verify payload redaction and delivery in a test project, exercise offline/restart/opt-out and physical-device lifecycle behavior, then ship through your normal app release process. Do not commit platform-owner credentials or provider keys to an app. Support: support@signaloryx.com.

## Device context

New error events include device/OS, app version/build, locale/timezone and runtime context as tags. Logs include the same data in attributes and now carry the configured environment. Android adds resource screen dimensions/density and Java heap usage; iOS adds physical memory, power mode and thermal state (numeric OS enum). No hardware identifiers, personal device names, location or network identifiers are collected. Set `collectDeviceContext` to `false` to disable collection; `beforeSend` can remove individual fields before persistence. Caller tags/attributes take precedence. Existing events cannot be backfilled. SDK updates must be integrated into a new mobile app release.

## iOS 0.3.0 session timeline (preview)

Version 0.3.0 sends bounded five-frame v2 batches with one stable session reference and retry-safe batch IDs. Simulator tests (15 cases), iOS compilation and an independent remote SPM consumer passed. Pin the published 0.3.0 tag and validate your actual app on physical devices before rollout. The updated backend/player joins uploads into a session timeline. No migration beyond existing 021 is required. Published 0.2.0 downloads do not contain this change; rebuild and release your app after validation.

Keep one recorder for the approved key window across navigation and ordinary foreground/background changes. Repeated valid starts return the same active recorder. Capture pauses while inactive/non-key/hidden or externally captured. Stop before account/window changes or sensitive workflows. No total-session timer is imposed by this collector; remove the older app-owned CappedReplay helper if full foreground-session capture is intended. Missing/background intervals remain gaps; this is UIKit geometry, not pixel video or full SwiftUI rendering.

```swift
// Main actor, after consent; retain the returned recorder.
let recorder = telemetry.startReplay(in: window, consentGranted: true, sampleRate: 1) // staging
recorder?.block(customerDetailsContainer)
recorder?.block(paymentContainer)
recorder?.allowPublicText(cartTitleLabel, text: "Your shopping bag")
recorder?.allowPublicText(errorMessageLabel, text: "Unable to update your cart. Please try again.")
// Before reusing this label for private content:
recorder?.maskText(errorMessageLabel)
// Consent withdrawal, without a preceding flush/normal stop:
telemetry.setEnabled(false)
```

Only UILabel/UIButton accept public annotations. Supply reviewed static messages, never actual view text, names, order IDs or arbitrary server responses. Blocks always win. Inputs, WebViews, image pixels and unapproved labels remain private. Public strings are limited to 160 characters and a 4 KiB encoded per-frame budget. Geometry is bounded to 128 nodes/32 levels. Already uploaded text cannot be recalled by changing an annotation. Use app-owned UIKit popup labels; system alerts and separate windows are not traversed. New recorders need blocks/annotations before their first one-second sample.

Validate a two-minute journey, quiet interval, scrolling, popup, background gap, repeated start, offline retry, opt-out, app restart, expiring sharing, deletion and tenant quota. Run simulator tests and measure physical-device overhead before release. Older recordings cannot recover omitted text.
