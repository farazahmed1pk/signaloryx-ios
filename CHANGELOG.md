# Native SDK releases

## iOS 0.3.0 - session replay preview

- Small UIKit frame batches now join into a foreground-session timeline with stable session references and idempotent batch IDs.
- Explicit static public UILabel/UIButton annotations; input/private/WebView masking remains mandatory and blocked ancestors win.
- Background flush/pause and repeated-start protection, with original-size and enlarged playback zoom.
- Current device-context source is included in the new iOS package. No pixel video, automatic SwiftUI rendering or system-alert capture.
- All 15 iOS simulator tests, iOS product compilation and independent remote SPM consumer passed. Android remains 0.2.0; previously published artifacts are unchanged. Physical-device app acceptance remains required.

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
