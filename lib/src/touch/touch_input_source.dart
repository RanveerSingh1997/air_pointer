import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/gestures.dart' as flutter_gestures;
import 'package:flutter/widgets.dart';

/// Mobile-native input source for Android and iOS.
///
/// Maps touch gestures to canvas events using direct-manipulation semantics:
///
/// | Gesture | Event |
/// |---|---|
/// | Short tap | [CanvasTapEvent] |
/// | Two taps within [doubleTapWindow] | [CanvasTapEvent] + [CanvasDoubleTapEvent] |
/// | Long press | [CanvasLongPressEvent] |
/// | Single-finger drag | [CanvasScrollEvent] (pan) |
/// | Flick / fling | [CanvasScrollEvent] with non-zero [CanvasScrollEvent.velocity] |
/// | Two-finger pinch or spread | [CanvasScaleEvent] |
/// | Two-finger release | [CanvasScaleEndEvent] |
/// | OS pointer cancel | [CanvasCancelEvent] |
///
/// **Delta convention** — [CanvasScrollEvent.delta] follows the same sign
/// convention as [MouseInputSource] scroll events: positive Y means the
/// viewport scrolls downward (content moves up). Use `offset -= delta` to pan
/// a canvas in the direction the finger dragged.
///
/// **Fling** — on release after a fast drag, [CanvasScrollEvent] is emitted
/// with [CanvasScrollEvent.delta] = [Offset.zero] and
/// [CanvasScrollEvent.velocity] set to the finger speed in pixels per second.
/// Positive velocity means the content should continue moving in that direction.
/// Use it to seed a momentum animation; zero velocity events are regular deltas.
///
/// **Tap detection** is done via raw [Listener] events (independent of the
/// gesture arena) so taps are never dropped by [ScaleGestureRecognizer]'s
/// movement threshold.
///
/// [CanvasHoverEvent] is never emitted — touchscreens have no hover cursor.
/// [CanvasDownEvent]/[CanvasUpEvent] are not emitted for single-finger drag;
/// pair with [MouseInputSource] in a [CanvasInputController] when both
/// element-drag (mouse) and canvas-pan (touch) are needed on the same surface.
final class TouchInputSource implements CanvasInputSource {
  TouchInputSource({
    this.behavior = HitTestBehavior.opaque,
    this.tapSlop = 10.0,
    this.doubleTapWindow = const Duration(milliseconds: 300),
  }) : _controller = StreamController.broadcast();

  final HitTestBehavior behavior;

  /// Maximum displacement (logical pixels) between press and release still
  /// treated as a tap rather than a pan.
  final double tapSlop;

  /// Maximum interval between two taps that qualifies as a double-tap.
  final Duration doubleTapWindow;

  final StreamController<PointerInputEvent> _controller;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => _TouchSurface(
        sink: _controller.sink,
        behavior: behavior,
        tapSlop: tapSlop,
        doubleTapWindow: doubleTapWindow,
        child: child,
      );

  @override
  void dispose() => unawaited(_controller.close());
}

class _TouchSurface extends StatefulWidget {
  const _TouchSurface({
    required this.sink,
    required this.behavior,
    required this.tapSlop,
    required this.doubleTapWindow,
    required this.child,
  });

  final EventSink<PointerInputEvent> sink;
  final HitTestBehavior behavior;
  final double tapSlop;
  final Duration doubleTapWindow;
  final Widget child;

  @override
  State<_TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<_TouchSurface> {
  // Pinch state (GestureDetector)
  bool _isPinching = false;
  double _pinchLastScale = 1.0;
  Offset _pinchLastFocalPoint = Offset.zero;

  // Scroll state (GestureDetector)
  Offset _scrollLastPosition = Offset.zero;

  // Tap state — tracked via raw Listener events, independent of gesture arena.
  // ScaleGestureRecognizer requires kPanSlop (~36px) of movement to win the
  // arena, which is larger than tapSlop (default 10px). Raw pointer events let
  // us distinguish taps from drags without depending on the arena outcome.
  bool _tapPending = false;
  Offset _pointerDownPosition = Offset.zero;
  bool _scrollEmitted = false; // true once onScaleUpdate fires
  DateTime? _lastTapTime;

  void _emit(PointerInputEvent event) => widget.sink.add(event);

  // ── Raw pointer events (tap detection) ──────────────────────────────────

  void _onPointerDown(flutter_gestures.PointerDownEvent e) {
    _tapPending = true;
    _pointerDownPosition = e.localPosition;
    _scrollEmitted = false;
  }

  void _onPointerUp(flutter_gestures.PointerUpEvent e) {
    if (_tapPending && !_isPinching && !_scrollEmitted) {
      final dist = (e.localPosition - _pointerDownPosition).distance;
      if (dist < widget.tapSlop) {
        _emitTap();
      }
    }
    _tapPending = false;
    _scrollEmitted = false;
  }

  void _onPointerCancel(flutter_gestures.PointerCancelEvent e) {
    _tapPending = false;
    _scrollEmitted = false;
    _isPinching = false;
    _emit(const CanvasCancelEvent());
  }

  void _emitTap() {
    final now = DateTime.now();
    final isDouble = _lastTapTime != null &&
        now.difference(_lastTapTime!) <= widget.doubleTapWindow;
    _emit(CanvasTapEvent(position: _pointerDownPosition));
    if (isDouble) {
      _emit(CanvasDoubleTapEvent(position: _pointerDownPosition));
      _lastTapTime = null;
    } else {
      _lastTapTime = now;
    }
  }

  // ── Gesture arena events (scroll / pinch) ───────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _isPinching = true;
      _pinchLastScale = 1.0;
      _pinchLastFocalPoint = details.localFocalPoint;
      return;
    }
    _scrollLastPosition = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isPinching) {
      _onPinchUpdate(details);
      return;
    }
    _scrollEmitted = true;
    // Negate finger movement so delta matches the MouseInputSource convention:
    // positive delta = viewport scrolls downward (content moves up), so
    // consumers doing `offset -= delta` pan in the direction of the drag.
    final delta = _scrollLastPosition - details.localFocalPoint;
    _scrollLastPosition = details.localFocalPoint;
    _emit(CanvasScrollEvent(position: details.localFocalPoint, delta: delta));
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    final scaleDelta =
        _pinchLastScale > 0 ? details.scale / _pinchLastScale : 1.0;
    final panDelta = details.localFocalPoint - _pinchLastFocalPoint;
    _pinchLastScale = details.scale;
    _pinchLastFocalPoint = details.localFocalPoint;
    _emit(
      CanvasScaleEvent(
        focalPoint: details.localFocalPoint,
        scaleDelta: scaleDelta,
        panDelta: panDelta,
      ),
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isPinching) {
      _isPinching = false;
      _pinchLastScale = 1.0;
      _emit(const CanvasScaleEndEvent());
      return;
    }
    _emitFling(details.velocity.pixelsPerSecond);
  }

  void _emitFling(Offset velocity) {
    if (velocity == Offset.zero) return;
    _emit(
      CanvasScrollEvent(
        position: _scrollLastPosition,
        delta: Offset.zero,
        velocity: velocity,
      ),
    );
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _tapPending = false;
    _lastTapTime = null;
    _emit(CanvasLongPressEvent(position: details.localPosition));
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: GestureDetector(
          behavior: widget.behavior,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onLongPressStart: _onLongPressStart,
          child: widget.child,
        ),
      );
}
