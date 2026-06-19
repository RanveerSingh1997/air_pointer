# air_pointer

Platform-agnostic canvas input abstraction for Flutter. Ships a `MouseInputSource`
for mouse/trackpad/touch and a `GestureInputSource` powered by MediaPipe
HandLandmarker for touchless control (Flutter Web only), both unified behind a
single `CanvasInputController` boundary — the canvas never knows which source
the events came from.

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
        MouseInputSource(),        // mouse, trackpad, touch
        GestureInputSource(),      // MediaPipe hand tracking (web only; no-op elsewhere)
      ],
    );
    _sub = _controller.events.listen(_onInput);
  }

  void _onInput(PointerInputEvent event) {
    switch (event) {
      case CanvasDownEvent(:final position):  // finger/cursor pressed
        ...
      case CanvasMoveEvent(:final position):  // dragging
        ...
      case CanvasUpEvent():                   // released
        ...
      case CanvasTapEvent(:final position):   // resolved tap (gesture arena winner)
        ...
      case CanvasHoverEvent(:final position): // hover (mouse only)
        ...
      case CanvasScrollEvent(:final delta):   // scroll wheel
        ...
      case CanvasScaleEvent(:final focalPoint, :final scaleDelta, :final panDelta):
        ...
      case CanvasScaleEndEvent():
        ...
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

## GestureInputSource (Flutter Web)

Add the MediaPipe CDN script to `web/index.html` before the Flutter bootstrap:

```html
<script src="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision_bundle.js"
        crossorigin="anonymous"></script>
<script src="flutter_bootstrap.js" async></script>
```

Then initialize the source after the canvas size is known:

```dart
final _gestureSource = GestureInputSource();

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  _gestureSource.updateCanvasSize(MediaQuery.sizeOf(context));
  unawaited(_gestureSource.initialize());
}
```

Pinch (thumb-tip to index-tip) maps to `CanvasDownEvent` / `CanvasMoveEvent` /
`CanvasUpEvent`. Position is smoothed with a `OneEuroFilter` and the x-axis is
mirrored so motion feels natural when facing the camera.

On non-web platforms `GestureInputSource` is a no-op stub — add it to the sources
list unconditionally and the platform conditional is handled inside the package.

## Architecture boundary

The strict rule: no `NormalizedLandmark`, `HandLandmarker`, `JSObject`, or any
`dart:js_interop` type may appear outside `lib/src/gesture/js/`. The boundary is
the `PointerInputEvent` sealed hierarchy — all sources speak the same sealed type.
