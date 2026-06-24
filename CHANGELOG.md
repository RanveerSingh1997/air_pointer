## 0.2.2 (unreleased)

### New

- **`TouchInputSource`** — mobile-native input source for Android and iOS.
  Single-finger drag → `CanvasScrollEvent` (direct-manipulation pan); two-finger
  pinch/spread → `CanvasScaleEvent`; fling → `CanvasScrollEvent` with non-zero
  `velocity` field for consumer momentum animations. Tap detection uses raw
  `Listener` events rather than `GestureDetector` so taps are never dropped by
  `ScaleGestureRecognizer`'s kPanSlop movement threshold.
- **`CanvasScrollEvent.velocity`** (`Offset`, default `Offset.zero`) — fling
  velocity field added to `CanvasScrollEvent`. Non-zero only on fling events
  emitted by `TouchInputSource`. Backwards-compatible: existing code that
  constructs or pattern-matches `CanvasScrollEvent` compiles unchanged.

### Documentation

- **README** — Documented three previously undocumented public API surfaces:
  `CanvasInputController` muting (`muteWhenActive`/`activeStream`),
  `GestureInputSource.statusStream` lifecycle states, and
  `GestureInputSource.setFilterParams()`.
- **README** — Added self-hosting section documenting `mediaPipeBaseUrl` and
  `modelAssetUrl` constructor parameters (Flutter Web only); corrected the
  "no self-hosted model" limitation which was inaccurate — self-hosting has
  been wired since 0.1.0.
- **KNOWN_LIMITATIONS** — Corrected "No rotation gesture" bullet: rotation IS
  emitted by `GestureInputSource` via `CanvasScaleEvent.rotation`; only
  `MouseInputSource` omits it (Flutter's `ScaleGestureRecognizer` limitation).
- **CONTRIBUTING** — Fixed wrong directory paths (`lib/src/filters/` →
  `lib/src/filter/`, removed non-existent `lib/src/calibration/`); added
  development prerequisites table.
- **SECURITY** — Replaced GitHub default template with accurate policy for a
  0.2.x package (correct version table, advisory link, SLA, scope table).
- **CLAUDE.md** — Added architecture guide for AI-assisted development,
  covering the js_interop boundary invariant, quality gates, testing philosophy,
  and breaking-change rules.

### Fixes

- `pubspec.yaml` version bumped from `0.2.0` to `0.2.1` (was incorrectly
  behind `CHANGELOG.md`); added `homepage` and `issue_tracker` fields.
- **`GestureInputSource` (native)** — `dispose()` now wraps `_frameSub?.cancel()`
  in `unawaited()`, consistent with the three `StreamController.close()` calls
  below it.

---

## 0.2.1

### Bug fixes

- **`MouseInputSource`** — `_lastTapTime` is now cleared in the drag path of
  `_onScaleEnd` so a tap followed by a quick drag no longer poisons the
  double-tap window for the next genuine tap.
- **`MouseInputSource`** — `_onPointerCancel` now resets `_isPinchZooming` and
  `_lastTapTime` so an OS-interrupted gesture cannot leave the source in
  pinch-zoom mode (causing the next tap to be swallowed as `CanvasScaleEndEvent`)
  or produce a spurious `CanvasDoubleTapEvent`.
- **`HandGestureRecognizer`** — the inter-tap timer (`_timeSinceLastDwellS`)
  now advances during `GesturePhase.down` (pinch-drag) and pointing-finger
  scroll so time spent in those phases correctly counts toward the double-tap
  window.
- **`HandGestureRecognizer`** — `_timeSinceLastDwellS` is reset to
  `double.infinity` when grace expires, preventing a stale tap from a previous
  tracking session from chaining as a double-tap on re-entry.
- **`HandGestureRecognizer`** — after a `CanvasDoubleTapEvent` fires,
  `_timeSinceLastDwellS` is reset to `double.infinity` instead of `0`,
  matching `MouseInputSource` behaviour (a third rapid dwell no longer emits a
  second double-tap).
- **`GestureInputSource` (native)** — `maxHands` constructor parameter is now
  stored as a readable `final int maxHands` field instead of being silently
  discarded; callers can query it when configuring their `LandmarkProvider`.
- **`CanvasGestureEvent`** — new `isSecondHand` field (`bool`, default `false`)
  distinguishes primary-hand gestures from secondary-hand gestures; both
  `GestureInputSource` backends now set `isSecondHand: true` on secondary-hand
  emissions.
- **`GestureInputSource` (web)** — `classifyGesture` is no longer called twice
  per frame per hand; the already-computed locals are reused when building
  `GestureDebugInfo`.
- **`GestureInputSource` (web)** — `recognized_gesture.dart` import sorted to
  correct alphabetical position (lint: `directives_ordering`).

---

## 0.2.0

### New events

- **`CanvasDoubleTapEvent`** — emitted alongside the second `CanvasTapEvent` when
  two taps occur within `doubleTapWindow` (default 300 ms). `MouseInputSource`
  detects it via a DateTime gap between releases; `HandGestureRecognizer` via
  elapsed time between consecutive dwell taps.
- **`CanvasLongPressEvent`** — emitted after the pointer (or cursor) holds still
  for `longPressDuration`. `MouseInputSource` uses `GestureDetector.onLongPressStart`;
  `HandGestureRecognizer` uses a configurable `longPressDuration` threshold shared
  with the dwell timer (shorter threshold always wins).
- **`CanvasGestureEvent(gesture)`** — edge-triggered on each `RecognizedGesture`
  change (non-none) for both the primary and secondary hand. Fires once when a
  gesture starts; resets when the hand is lost so the same gesture can fire again
  on re-entry.

### HandGestureRecognizer

- `longPressDuration` — new constructor param; `Duration.zero` = disabled (default).
- `doubleTapWindow` — new constructor param controlling the inter-tap interval
  that qualifies as a double tap (default 300 ms).
- `longPressDurationS` / `doubleTapWindowS` — public getters for the above.
- Pointing-finger scroll now emits both horizontal and vertical deltas
  (`Offset(scrollDx, scrollDy)` instead of `Offset(0, scrollDy)`).
- `_checkDwell` refactored to `_checkDwellEvents` returning
  `List<PointerInputEvent>` to support multiple simultaneous events (tap +
  double-tap).

### MouseInputSource

- **`CanvasCancelEvent`** emitted from `Listener.onPointerCancel` when the OS
  interrupts an active drag (context menu, window switch, etc.).
- **`CanvasLongPressEvent`** via `GestureDetector.onLongPressStart`. If a drag
  was in progress, `CanvasCancelEvent` is emitted first to close it cleanly.
- **Double-tap** detected via a `DateTime` gap between successive tap releases.

### GestureInputSource

- `longPressDuration` and `doubleTapWindow` forwarded to `HandGestureRecognizer`
  on both web and native variants.
- `maxHands` param (default 2) forwarded to the MediaPipe web worker's
  `numHands` option; set to 1 to improve performance in single-hand apps.
- `CanvasGestureEvent` emitted for secondary hand gestures in addition to the
  primary hand.
- `_lastGesture` resets to `none` when tracking is lost, so the same gesture
  fires again when the hand re-enters the frame.

### Breaking changes

- `OneEuroFilter` removed from the public barrel export (`air_pointer.dart`).
  It was an internal smoothing detail; import directly from
  `package:air_pointer/src/filter/one_euro_filter.dart` if needed.

---

## 0.1.0

Initial release.

### Events

- **`PointerInputEvent` sealed hierarchy** — `CanvasTapEvent`, `CanvasDownEvent`,
  `CanvasMoveEvent`, `CanvasUpEvent`, `CanvasCancelEvent`, `CanvasHoverEvent`,
  `CanvasScrollEvent` (with `isTrackpad`), `CanvasScaleEvent` (with `rotation`),
  `CanvasScaleEndEvent`, `CanvasSwipeEvent` (with `SwipeDirection` and `velocity`).
  All events use the `Canvas` prefix to avoid collisions with Flutter's own pointer events.

### Core abstractions

- **`CanvasInputSource`** — abstract boundary; all input origins implement this contract.
- **`CanvasInputController`** — merges events from multiple `CanvasInputSource`s into a
  single broadcast stream; folds `buildSurface` wrappers in order.

### MouseInputSource

- Maps Flutter gesture-arena callbacks to canvas events: tap → `CanvasTapEvent`,
  one-finger drag → Down/Move/Up, two-finger pinch → `CanvasScaleEvent`, scroll wheel
  and native trackpad pinch (`PointerScaleEvent`) → `CanvasScrollEvent` /
  `CanvasScaleEvent`, mouse hover → `CanvasHoverEvent`.
- `scrollMultiplier` — scales scroll deltas before emission.
- `tapSlop` — configurable tap-slop threshold (default 10 px).
- `isTrackpad` on `CanvasScrollEvent` — true for macOS/iOS two-finger pan; consumers can
  skip ticker-based inertia since the OS already provides momentum.

### GestureInputSource (Flutter Web)

MediaPipe HandLandmarker running in a dedicated web worker (off the main thread).
Zero-copy `ImageBitmap` transfer. Camera permission / hardware / context errors all
produce typed `HandTrackingStatus` states.

- **`HandGestureRecognizer`** — pure-Dart state machine; fully testable without a camera.
  - Acquisition gate: N consecutive frames (default 3) to confirm hand presence.
  - Hysteresis: separate close (default 0.05) and open (default 0.08) thresholds prevent
    chatter near the boundary.
  - Grace window: N frames (default 5) before declaring the hand lost; cursor freezes and
    dwell progress is preserved through brief occlusions.
  - Clutch / Midas-touch guard: pinch is blocked until the hand opens after confirmation,
    preventing accidental drags when the hand enters the frame already pinched.
  - `CanvasCancelEvent` (not `CanvasUpEvent`) when the hand exits during an active drag.
  - Two-hand spread → `CanvasScaleEvent` with rotation delta;
    `CanvasScaleEndEvent` when the second hand leaves.
  - Dwell-click: cursor must hold still within `dwellRadius` for `dwellDuration` to emit
    `CanvasTapEvent`. Progress is reported via `GestureDebugInfo.dwellProgress` (0–1).
    Dwell is preserved through the grace window so brief occlusions don't reset progress.
  - Pointing-finger scroll: index extended + middle curled → `CanvasScrollEvent` driven by
    vertical fingertip movement. Enabled via `scrollEnabled: true`; scaled by `scrollScale`.
  - Swipe gesture: fast directional movement (velocity > `swipeThreshold` px/s) in an
    open hand emits `CanvasSwipeEvent`. 60/40 dominance ratio prevents diagonal
    false-positives; 400 ms cooldown suppresses repeated firing from one gesture.
    Disabled by default (`swipeThreshold: 0`).
- **`OneEuroFilter`** — adaptive low-pass filter (Casiez et al., CHI 2012) for landmark
  coordinates. Exposes `velocity` for prediction and swipe detection.
- **`GestureCalibrator`** — accumulates open/closed pose samples from
  `GestureDebugInfo.pinchDistance` and computes per-user `CalibrationResult`.
- **`LandmarkProvider`** — platform interface for native landmark sources (e.g. TFLite on
  iOS/Android); web implementation uses MediaPipe via web worker.
- **Debug support** — `GestureInputSource.debugInfo` stream of `GestureDebugInfo`
  (phase, pinch distance, dwell progress, pointing flag, landmarks, worker latency,
  round-trip latency). `buildCameraPreview` returns a live camera widget.

### Example

`example/` ships two demos driven entirely through `CanvasInputController`:

- **Sandbox canvas** — draggable boxes with dot-grid background, inertia scrolling,
  two-finger pinch-to-zoom, dwell-click, pointing-finger scroll, debug overlay,
  camera preview, calibration dialog, and zoom badge.
- **Netflix-style demo** — scrollable content grid with hero section, card rows with
  horizontal scrolling, detail overlay, and full air-pointer interaction (pinch-drag with
  inertia, dwell-click with progress ring, pointing scroll, swipe navigation).
