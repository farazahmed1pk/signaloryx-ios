# Signaloryx for iOS

Swift package for explicit errors, messages, breadcrumbs, logs and transactions. iOS 13+, Swift tools 5.9. Product: `Signaloryx`.

## Install with Swift Package Manager

Official SDK-only repository: `https://github.com/farazahmed1pk/signaloryx-ios.git`. Use an available published release tag; consult the [mobile integration guide](https://signaloryx.com/docs/mobile-integration) for publication status. In Xcode select **File → Add Package Dependencies**, enter that URL, select the published version and add the **Signaloryx** product to your app target. Do not use the private application repository.

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

See the [integration guide](https://signaloryx.com/docs/mobile-integration) for redaction, queue limits, opt-out, offline tests and lifecycle limitations. No automatic fatal crashes, native replay or symbolication. Versioned downloads remain an offline alternative.

## Maintenance

Review CHANGELOG and migration notes, update the pinned version in a branch, verify payload redaction and delivery in a test project, exercise offline/restart/opt-out and physical-device lifecycle behavior, then ship through your normal app release process. Do not commit platform-owner credentials or provider keys to an app. Support: support@signaloryx.com.
