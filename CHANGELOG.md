# Native SDK releases

## 0.2.0 — native wireframe replay preview

- Opt-in, sampled Android View and UIKit wireframe capture, with no text/image/pixel collection.
- Five-frame batches through the existing persistent queue, beforeSend and consent purge.
- Native replay protocol validation and dashboard playback/seek.
- Android and iOS simulator/collector tests passed; physical-device performance and app privacy acceptance remain deployment checks.

## 0.1.0 — initial preview

- Android API 23+ and Swift iOS 13+ explicit instrumentation.
- Handled exceptions/messages, breadcrumbs, logs and manually timed transactions.
- Bounded persistent queue, retry policy, beforeSend redaction and consent opt-out.
- Dependency-manager release preparation: remote SPM package and signed Maven AAR, source/Javadoc artifacts and dependency metadata.

No automatic fatal-crash capture, Android ANR/NDK capture, native replay, symbolication or automatic tracing. Background/terminated delivery is not guaranteed. Physical-device validation remains required. This version is a preview; review upgrades explicitly.
