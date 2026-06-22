# air_pointer

Platform-agnostic canvas input abstraction for Flutter. Ships a `MouseInputSource`
for mouse/trackpad/touch and a `GestureInputSource` powered by MediaPipe
HandLandmarker for touchless hand control (Flutter Web only), both unified behind
a single `CanvasInputController` — the canvas never knows which source the events
came from.

---

## Quick start

```dart
import 'package:air_pointer/air_pointer.dart';

class MyCanvasState extends State<MyCanvas> {
  late final CanvasInputController _controller;
  late final StreamSubscription<PointerInputEvent> _sub;

  @override
  void initState() {
    super.initState();
    _controller = CanvasInputController(
      sources: [
        MouseInputSource(),     // mouse, trackpad, touch
        GestureInputSource(),   // MediaPipe hand tracking (web only; no-op elsewhere)
      ],
    );
    _sub = _controller.events.listen(_onInput);
  }

  void _onInput(PointerInputEvent event) {
    switch (event) {
      case CanvasTapEvent(:final position):
        // resolved tap (no drag)
      case CanvasDoubleTapEvent(:final position):
        // second tap within the double-tap window (~300 ms)
        // always preceded by CanvasTapEvent on the same frame
      case CanvasLongPressEvent(:final position):
        // pointer held still beyond the long-press threshold
      case CanvasDownEvent(:final position):
        // drag/pinch started
      case CanvasMoveEvent(:final position):
        // drag in progress
      case CanvasUpEvent(:final position):
        // released — commit the action
      case CanvasCancelEvent():
        // drag interrupted (e.g. hand left the camera mid-drag) — discard it
      case CanvasHoverEvent(:final position):
        // cursor hovering (no button held)
      case CanvasScrollEvent(:final position, :final delta, :final isTrackpad):
        // scroll wheel or pointing-finger scroll
      case CanvasScaleEvent(:final focalPoint, :final scaleDelta, :final panDelta):
        // pinch-to-zoom (two fingers or two hands)
      case CanvasScaleEndEvent():
        // scale gesture ended
      case CanvasSwipeEvent(:final direction, :final velocity):
        // fast directional motion in an open hand
      case CanvasGestureEvent(:final gesture, :final isSecondHand):
        // discrete gesture recognised (thumbsUp, victory, etc.)
        // isSecondHand is true when it came from the second detected hand
    }
  }

  @override
  Widget build(BuildContext context) => _controller.buildSurface(
        child: MyCanvasPainter(...),
      );

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }
}
```

---

## Event type reference

| Type | Fields | Description |
|---|---|---|
| `CanvasTapEvent` | `position` | Resolved tap (no drag) |
| `CanvasDoubleTapEvent` | `position` | Second tap within the double-tap window; always preceded by `CanvasTapEvent` |
| `CanvasLongPressEvent` | `position` | Pointer held still beyond the long-press threshold |
| `CanvasDownEvent` | `position` | Drag/pinch started |
| `CanvasMoveEvent` | `position` | Drag in progress |
| `CanvasUpEvent` | `position` | Drag ended — commit |
| `CanvasCancelEvent` | — | Drag aborted — discard |
| `CanvasHoverEvent` | `position` | Hover (no press) |
| `CanvasScrollEvent` | `position`, `delta`, `isTrackpad` | Scroll wheel or pointing-finger scroll |
| `CanvasScaleEvent` | `focalPoint`, `scaleDelta`, `panDelta`, `rotation` | Pinch/spread with optional rotation |
| `CanvasScaleEndEvent` | — | Scale gesture ended |
| `CanvasSwipeEvent` | `direction`, `velocity` | Fast directional cursor movement |
| `CanvasGestureEvent` | `gesture`, `isSecondHand` | Discrete hand gesture (edge-triggered on change) |

---

## GestureInputSource (Flutter Web only)

### 1. Add the MediaPipe CDN script

In `web/index.html`, before `flutter_bootstrap.js`:

```html
<script src="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision_bundle.js"
        crossorigin="anonymous"></script>
<script src="flutter_bootstrap.js" async></script>
```

### 2. Copy the worker script

Place `hand_tracker_worker.js` (from `example/web/`) next to your
`index.html`. The worker runs MediaPipe inference off the main thread.

### 3. Initialize the source

```dart
final _gestureSource = GestureInputSource(
  onError: (e, st) => print('hand tracking: $e'),
  dwellDuration: const Duration(milliseconds: 700),  // enable dwell-tap
  doubleTapWindow: const Duration(milliseconds: 300),
  longPressDuration: const Duration(milliseconds: 1200),
  scrollEnabled: true,
  maxHands: 2,  // set to 1 for better performance in single-hand apps
);

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Pass the canvas size so cursor coordinates are in screen pixels.
  _gestureSource.updateCanvasSize(MediaQuery.sizeOf(context));
  unawaited(_gestureSource.initialize());
}
```

`initialize()` is idempotent — safe to call from `didChangeDependencies`.

### Gesture mapping

| Hand gesture | Event |
|---|---|
| Open hand, fingertip moves | `CanvasHoverEvent` |
| Pinch (thumb + index < 5 % gap) | `CanvasDownEvent` |
| Hold pinch + move | `CanvasMoveEvent` |
| Release pinch | `CanvasUpEvent` |
| Hand exits frame mid-drag | `CanvasCancelEvent` (discard, not commit) |
| Cursor holds still for `dwellDuration` | `CanvasTapEvent` |
| Second dwell within `doubleTapWindow` | `CanvasTapEvent` + `CanvasDoubleTapEvent` |
| Cursor holds still for `longPressDuration` | `CanvasLongPressEvent` |
| Index finger extended, move up/down | `CanvasScrollEvent` (when `scrollEnabled: true`) |
| Fast directional motion, open hand | `CanvasSwipeEvent` (when `swipeThreshold > 0`) |
| Two-hand spread/pinch | `CanvasScaleEvent` with `rotation` |
| Two hands separate | `CanvasScaleEndEvent` |
| Recognised discrete gesture | `CanvasGestureEvent` (edge-triggered; `isSecondHand` for the second hand) |

Position is smoothed with a `OneEuroFilter` and the x-axis is mirrored so
motion feels natural facing the front camera.

### Dwell-tap

Dwell-tap lets users click without a physical button — the cursor fires
`CanvasTapEvent` after holding still within `dwellRadius` pixels for `dwellDuration`:

```dart
GestureInputSource(
  dwellDuration: const Duration(milliseconds: 700),
  dwellRadius: 12.0,
)
```

`GestureDebugInfo.dwellProgress` (0–1) drives a progress ring in the example app.
Progress is preserved through the grace window so brief occlusions don't reset it.

### Double-tap and long-press

Both `GestureInputSource` and `MouseInputSource` fire the same events:

```dart
GestureInputSource(
  dwellDuration: const Duration(milliseconds: 500),
  doubleTapWindow: const Duration(milliseconds: 300),  // time between two taps
  longPressDuration: const Duration(milliseconds: 1200),
)

MouseInputSource()  // double-tap via DateTime gap; long-press via GestureDetector (~500 ms)
```

`CanvasDoubleTapEvent` is always preceded by `CanvasTapEvent` on the same frame so
consumers that only handle single tap continue to work.

### Discrete gesture events

`CanvasGestureEvent` fires once when a `RecognizedGesture` value first appears,
then rearms when the hand is lost so re-entry with the same gesture fires again:

```dart
case CanvasGestureEvent(:final gesture, :final isSecondHand):
  if (!isSecondHand) {
    switch (gesture) {
      case RecognizedGesture.thumbUp:   _undo();
      case RecognizedGesture.victory:   _redo();
      case RecognizedGesture.openPalm:  _showMenu();
      default: break;
    }
  }
```

Supported values: `thumbUp`, `thumbDown`, `openPalm`, `closedFist`, `victory`,
`pointingUp`, `iLoveYou`, `none`.

### Camera preview

```dart
_gestureSource.buildCameraPreview(width: 240, height: 180)
```

Returns a widget with a live mirrored feed. Shows a placeholder until the
camera is ready, and an error card if initialization failed.

### Debug overlay

Subscribe to `GestureInputSource.debugInfo` for per-frame `GestureDebugInfo`
snapshots (phase, pinch distance, dwell progress, landmarks, detected gestures,
worker latency). Use them to build a custom debug overlay — the example app
(`example/`) has a ready-made one.

---

## MouseInputSource options

```dart
MouseInputSource(
  tapSlop: 10.0,           // max displacement (px) still treated as a tap
  scrollMultiplier: 1.0,   // scale scroll deltas (e.g. 1/zoomLevel)
)
```

`CanvasScrollEvent.isTrackpad` is `true` for macOS/iOS two-finger pan; the OS
already applies momentum so consumers should skip extra inertia for those events.

Double-tap is detected via a 300 ms gap between tap releases. Long-press uses
Flutter's `GestureDetector.onLongPressStart` (~500 ms threshold). If a drag was
in progress when long-press fires, `CanvasCancelEvent` is emitted first.

---

## Per-user calibration

Default thresholds (pinch close = 0.05, open = 0.08) work for most hands in
good lighting. For users with small hands, unusual skin tone, or dim
environments, run a quick calibration:

```dart
// 1. Collect samples via GestureCalibrator (reads pinch distance from debugInfo).
final calibrator = GestureCalibrator();

// Call addOpenSample / addCloseSample each frame from your debugInfo subscription:
// calibrator.addOpenSample(info.pinchDistance);   // while hand is open
// calibrator.addCloseSample(info.pinchDistance);  // while hand is pinching

// 2. Compute thresholds when both poses are collected.
final result = calibrator.compute(); // null if insufficient data
if (result != null) {
  gestureSource.applyCalibration(result);
}
```

The example app ships a `CalibrationDialog` widget that handles the full
guided flow.

---

## Native hand tracking (non-web)

On iOS, Android, macOS, Windows, and Linux the web worker is unavailable.
Use the `LandmarkProvider` interface to connect any native ML backend:

```dart
class MyTFLiteProvider implements LandmarkProvider {
  final _ctrl = StreamController<HandDetectionFrame>.broadcast();

  @override
  Stream<HandDetectionFrame> get frames => _ctrl.stream;

  void onInferenceResult(List<HandLandmarkPoint> lms) {
    _ctrl.add(HandDetectionFrame(landmarks: lms));
  }

  @override
  Widget buildPreview({double? width, double? height}) => CameraPreview(...);

  @override
  void dispose() { _ctrl.close(); }
}

final source = GestureInputSource(
  landmarkProvider: MyTFLiteProvider(),
  maxHands: 1,  // query source.maxHands to configure your provider
  dwellDuration: const Duration(milliseconds: 700),
);
```

`HandGestureRecognizer` is the pure-Dart state machine that drives all event
logic — it is fully unit-testable without a camera or ML model.

---

## Architecture boundary

The strict invariant: **no `NormalizedLandmark`, `HandLandmarker`, `JSObject`,
or any `dart:js_interop` type may appear outside `lib/src/gesture/`**. The
`PointerInputEvent` sealed hierarchy is the only currency that crosses the
boundary — all sources speak the same type.

---

## Known limitations

- **Flutter Web only for MediaPipe.** `GestureInputSource` requires a
  `LandmarkProvider` on native platforms. The web implementation is self-contained
  (MediaPipe via web worker); native requires you to wire up your own ML backend.

- **Requires a secure context.** `getUserMedia` only works on `https://` or
  `localhost`. Serving over plain `http://` will produce a camera permission error.

- **Lighting sensitivity.** Tracking degrades in dim or strongly backlit
  conditions. MediaPipe's model is generally robust across skin tones but
  performance may vary. Run calibration if default thresholds are unreliable.

- **No offline/self-hosted model.** The WASM runtime and `.task` model file are
  loaded from CDN at runtime. Self-hosting is possible by downloading the assets
  and updating the paths — not yet wired as a package option.

- **First-run CDN latency.** MediaPipe WASM (~4 MB) loads before the first frame
  is processed. On a cold cache this takes 2–5 seconds. Subsequent page loads use
  the browser cache.

- **`CanvasCancelEvent` has no position.** When a hand exits the frame mid-drag,
  the last known position is not re-emitted. Consumers that need a "cancel at
  position" snapshot should cache `_lastPosition` from the preceding
  `CanvasMoveEvent`.
