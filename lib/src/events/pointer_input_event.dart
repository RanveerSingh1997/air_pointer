import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter/painting.dart';

sealed class PointerInputEvent {
  const PointerInputEvent();
}

final class CanvasTapEvent extends PointerInputEvent {
  const CanvasTapEvent({required this.position});

  final Offset position;
}

/// Emitted when two [CanvasTapEvent]s occur within the double-tap window
/// (~300 ms by default). Always preceded by a [CanvasTapEvent] on the same
/// frame so consumers that only handle single-tap still work correctly.
final class CanvasDoubleTapEvent extends PointerInputEvent {
  const CanvasDoubleTapEvent({required this.position});

  final Offset position;
}

/// Emitted when the cursor holds still beyond the long-press threshold.
///
/// Fired by [GestureInputSource] when `longPressDuration > Duration.zero`.
/// Fired by [MouseInputSource] after the pointer is held without movement for
/// ~500 ms (via [GestureDetector.onLongPressStart]).
final class CanvasLongPressEvent extends PointerInputEvent {
  const CanvasLongPressEvent({required this.position});

  final Offset position;
}

final class CanvasDownEvent extends PointerInputEvent {
  const CanvasDownEvent({
    required this.position,
    this.pressure = 1.0,
    this.tilt = 0.0,
    this.orientation = 0.0,
  });

  final Offset position;

  /// Pen/stylus contact pressure in the range 0.0–1.0.
  /// Always 1.0 for mouse and touch events.
  final double pressure;

  /// Stylus tilt angle in radians from the surface plane (0.0 = flat,
  /// π/2 = perpendicular). Always 0.0 for mouse and touch events.
  final double tilt;

  /// Stylus azimuth angle in radians relative to the positive X axis,
  /// clockwise (0.0 = pointing right). Always 0.0 for mouse and touch events.
  final double orientation;
}

final class CanvasMoveEvent extends PointerInputEvent {
  const CanvasMoveEvent({
    required this.position,
    this.pressure = 1.0,
    this.tilt = 0.0,
    this.orientation = 0.0,
  });

  final Offset position;

  /// Pen/stylus contact pressure in the range 0.0–1.0.
  /// Always 1.0 for mouse and touch events.
  final double pressure;

  /// Stylus tilt angle in radians from the surface plane (0.0 = flat,
  /// π/2 = perpendicular). Always 0.0 for mouse and touch events.
  final double tilt;

  /// Stylus azimuth angle in radians relative to the positive X axis,
  /// clockwise (0.0 = pointing right). Always 0.0 for mouse and touch events.
  final double orientation;
}

final class CanvasUpEvent extends PointerInputEvent {
  const CanvasUpEvent({required this.position});

  final Offset position;
}

final class CanvasHoverEvent extends PointerInputEvent {
  const CanvasHoverEvent({required this.position});

  final Offset position;
}

final class CanvasScrollEvent extends PointerInputEvent {
  const CanvasScrollEvent({
    required this.position,
    required this.delta,
    this.isTrackpad = false,
    this.velocity = Offset.zero,
  });

  final Offset position;
  final Offset delta;

  /// True when the scroll originated from a trackpad (e.g. macOS two-finger
  /// pan). The OS already applies momentum scrolling for trackpad events, so
  /// consumers should apply the delta directly rather than adding extra inertia.
  final bool isTrackpad;

  /// Fling velocity in pixels per second, in content-movement coordinates.
  ///
  /// Non-zero only on touch fling events emitted by [TouchInputSource] at the
  /// end of a fast single-finger drag. Positive X = content moving right;
  /// positive Y = content moving down. Use it to seed a momentum animation —
  /// [delta] is [Offset.zero] on fling events so only one field is non-zero at
  /// a time.
  final Offset velocity;
}

final class CanvasScaleEvent extends PointerInputEvent {
  const CanvasScaleEvent({
    required this.focalPoint,
    required this.scaleDelta,
    required this.panDelta,
    this.rotation = 0.0,
  });

  final Offset focalPoint;

  /// Multiplicative scale factor: 1.05 = 5% zoom in, 0.95 = 5% zoom out.
  final double scaleDelta;
  final Offset panDelta;

  /// Rotation delta in radians; positive = clockwise in screen coordinates.
  final double rotation;
}

final class CanvasScaleEndEvent extends PointerInputEvent {
  const CanvasScaleEndEvent();
}

/// Emitted when a drag is interrupted by an unrecoverable event (e.g. the
/// hand tracking hand exits the camera frame mid-drag).
///
/// Unlike [CanvasUpEvent], cancel signals that the action should NOT be
/// committed — consumers should roll back or discard any in-progress change.
final class CanvasCancelEvent extends PointerInputEvent {
  const CanvasCancelEvent();
}

/// Emitted when the hand-tracking backend classifies a discrete gesture
/// (e.g. thumbs-up, victory sign). Only fired by [GestureInputSource] when
/// the [RecognizedGesture] value is not [RecognizedGesture.none].
///
/// The event is emitted once per gesture recognition, not every frame.
/// Consumers can bind app-specific actions to each gesture value.
final class CanvasGestureEvent extends PointerInputEvent {
  const CanvasGestureEvent({required this.gesture, this.isSecondHand = false});

  final RecognizedGesture gesture;

  /// True when the gesture was detected on the secondary (second) hand.
  final bool isSecondHand;
}

/// Cardinal direction of a [CanvasSwipeEvent].
enum SwipeDirection { up, down, left, right }

/// Emitted when the cursor moves fast enough in a single direction to be
/// classified as a swipe gesture.
///
/// Only fired by [GestureInputSource] when `swipeThreshold > 0`. The cursor
/// continues emitting [CanvasHoverEvent] alongside the swipe, so consumers
/// do not need to separately track position.
///
/// [velocity] is the cursor speed in screen pixels per second at the moment
/// the swipe was detected.
final class CanvasSwipeEvent extends PointerInputEvent {
  const CanvasSwipeEvent({required this.direction, required this.velocity});

  final SwipeDirection direction;

  /// Cursor speed in screen pixels per second.
  final double velocity;
}
