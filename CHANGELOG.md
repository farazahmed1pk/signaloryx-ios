# Native SDK releases

## Android + iOS 0.5.0 candidate - recording safety limits (unpublished)

- `replayMaxSessionDurationSeconds`: default 900 (15 minutes), range 60–14400. Monotonic elapsed time includes pauses; final batches are clipped at the cap.
- Stops without automatic restart. Explicit `stopReplay()` and a new consented start creates a new recording.
- Server HTTP 410 drops queued replay uploads and stops only its matching recorder. A delayed response cannot stop a newer session. Errors/logs remain independent.
- Tenant duration/size caps require backend migration 022. Lower client/tenant limits win; masking and Compose/SwiftUI support remain unchanged.
- Candidate only; released 0.4.0 tags, downloads and PDF remain unchanged.

## Android + iOS 0.4.0 - display text and supported framework adapters

- Ordinary display labels/buttons are visible by default after consent. Mark customer-data labels/subtrees before the first sample; use replayMaskAllText=true to retain mask-all behavior.
- Reversible mask/unmask and block/unblock controls; inputs/passwords, WebViews, protected windows and private ancestors stay protected. Privacy scans and Android registration overflow fail closed.
- Optional signaloryx-compose module with BasicText wrapper, display-text, input and mask modifiers, using supported layout/composition APIs.
- SwiftUI iOS 14+ Text wrapper and View modifiers, including private bounds over embedded UIKit content. UIKit remains iOS 13+.
- Native protocol v3, bounded 256-node display wireframes; legacy v1/v2 playback preserved. Full-session grouping, consent revoke and retention behavior remain intact.
- Android: 25 Robolectric/core/Compose tests plus lint/build passed. iOS: 20 simulator tests, product build and independent SPM consumer passed. Physical-device app privacy, lazy-list and performance acceptance remain required.
- Hosted Android core/Compose AARs and source; official iOS SPM repository/tag. Android Maven Central publication remains pending. No image/pixel/system-window recording.
- Updated platform and PDF guide with Compose, SwiftUI, masking, public popup, full-session lifecycle, revoke and test examples.

## Android 0.3.0 - session replay preview

- Bounded View frame uploads join into one session timeline, with stable session references, idempotent batch IDs and Activity pause/resume continuity.
- New `pauseReplay()` preserves the logical session across approved Activities; `stopReplay()` ends it. Repeated starts preserve sampling and the recorder.
- `NativeReplay.allowPublicText(TextView, String)` and `maskText(View)` show reviewed static public labels/buttons and in-window popup messages; parent blocks, EditText/password and WebView protection remain enforced.
- Opaque backgrounds and approved text color/font size improve wireframe recognition. No pixel video, automatic Compose, system/separate-window popup or input-value capture.
- Hosted versioned AAR/source distribution. Maven Central publication remains pending. Robolectric/lint/consumer validation does not replace emulator/physical-device app acceptance.
- Updated mobile PDF and platform examples include full-session lifecycle, consent revoke, public popup annotations and regression checklist. Earlier published Android/iOS artifacts remain unchanged.

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
