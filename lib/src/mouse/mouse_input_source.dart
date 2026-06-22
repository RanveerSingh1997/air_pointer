import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/gestures.dart' as flutter_gestures;
import 'package:flutter/widgets.dart';

final class MouseInputSource implements CanvasInputSource {
  MouseInputSource({
    this.behavior = HitTestBehavior.opaque,
    this.tapSlop = 10.0,
    this.scrollMultiplier = 1.0,
  }) : _controller = StreamController.broadcast();

  final HitTestBehavior behavior;

  /// Maximum displacement (in logical pixels) between press and release that
  /// is still treated as a tap rather than a drag.
  final double tapSlop;

  /// Multiplier applied to every [CanvasScrollEvent] delta.
  ///
  /// Useful when the canvas has a zoom level and you want scroll speed to
  /// track it (e.g. `scrollMultiplier: 1.0 / _scale`).
  final double scrollMultiplier;

  final StreamController<PointerInputEvent> _controller;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => _MouseSurface(
        sink: _controller.sink,
        behavior: behavior,
        tapSlop: tapSlop,
        scrollMultiplier: scrollMultiplier,
        child: child,
      );

  @override
  void dispose() => unawaited(_controller.close());
}

class _MouseSurface extends StatefulWidget {
  const _MouseSurface({
    required this.sink,
    required this.behavior,
    required this.tapSlop,
    required this.scrollMultiplier,
    required this.child,
  });

  final EventSink<PointerInputEvent> sink;
  final HitTestBehavior behavior;
  final double tapSlop;
  final double scrollMultiplier;
  final Widget child;

  @override
  State<_MouseSurface> createState() => _MouseSurfaceState();
}

class _MouseSurfaceState extends State<_MouseSurface> {
  bool _isPinchZooming = false;
  double _pinchLastScale = 1.0;
  Offset _pinchLastFocalPoint = Offset.zero;
  bool _hasDragStarted = false;
  Offset _dragLastPosition = Offset.zero;
  Offset _downPosition = Offset.zero;
  DateTime? _lastTapTime;

  void _emit(PointerInputEvent event) => widget.sink.add(event);

  void _onPointerHover(flutter_gestures.PointerHoverEvent e) =>
      _emit(CanvasHoverEvent(position: e.localPosition));

  void _onPointerSignal(flutter_gestures.PointerSignalEvent e) {
    if (e is flutter_gestures.PointerScrollEvent) {
      _emit(
        CanvasScrollEvent(
          position: e.localPosition,
          delta: e.scrollDelta * widget.scrollMultiplier,
          isTrackpad: e.kind == PointerDeviceKind.trackpad,
        ),
      );
    } else if (e is flutter_gestures.PointerScaleEvent) {
      // Native trackpad pinch-to-zoom on macOS/iOS Flutter. scale is a
      // per-event delta (1.05 = 5% zoom in), matching CanvasScaleEvent's
      // scaleDelta contract. No end event is synthesized — each event is
      // self-contained, so we emit CanvasScaleEndEvent immediately after.
      _emit(
        CanvasScaleEvent(
          focalPoint: e.localPosition,
          scaleDelta: e.scale,
          panDelta: Offset.zero,
        ),
      );
      _emit(const CanvasScaleEndEvent());
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _isPinchZooming = true;
      _pinchLastScale = 1.0;
      _pinchLastFocalPoint = details.localFocalPoint;
      return;
    }
    _isPinchZooming = false;
    _hasDragStarted = true;
    _downPosition = details.localFocalPoint;
    _dragLastPosition = details.localFocalPoint;
    _emit(CanvasDownEvent(position: details.localFocalPoint));
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isPinchZooming) {
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
      return;
    }
    _dragLastPosition = details.localFocalPoint;
    _emit(CanvasMoveEvent(position: details.localFocalPoint));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isPinchZooming) {
      _isPinchZooming = false;
      _pinchLastScale = 1.0;
      _emit(const CanvasScaleEndEvent());
      return;
    }
    if (_hasDragStarted) {
      _hasDragStarted = false;
      // Distinguish tap from drag: if total movement stayed within the slop
      // threshold, treat it as a tap rather than a drag-end. This avoids
      // registering TapGestureRecognizer (which would compete with
      // ScaleGestureRecognizer in the arena and delay onScaleStart by ~18 px).
      final wasTap =
          (_dragLastPosition - _downPosition).distance < widget.tapSlop;
      if (wasTap) {
        final now = DateTime.now();
        final isDouble = _lastTapTime != null &&
            now.difference(_lastTapTime!) <=
                const Duration(milliseconds: 300);
        _emit(CanvasTapEvent(position: _downPosition));
        if (isDouble) {
          _emit(CanvasDoubleTapEvent(position: _downPosition));
          _lastTapTime = null;
        } else {
          _lastTapTime = now;
        }
      } else {
        _emit(CanvasUpEvent(position: _dragLastPosition));
      }
    }
  }

  void _onPointerCancel(flutter_gestures.PointerCancelEvent e) {
    if (_hasDragStarted) {
      _hasDragStarted = false;
      _emit(const CanvasCancelEvent());
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_hasDragStarted) {
      _hasDragStarted = false;
      _emit(const CanvasCancelEvent());
    }
    _emit(CanvasLongPressEvent(position: details.localPosition));
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
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
