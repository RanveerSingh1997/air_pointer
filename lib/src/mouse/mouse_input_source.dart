import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/gestures.dart' as flutter_gestures;
import 'package:flutter/widgets.dart';

final class MouseInputSource implements CanvasInputSource {
  MouseInputSource({
    this.behavior = HitTestBehavior.opaque,
  }) : _controller = StreamController.broadcast();

  final HitTestBehavior behavior;
  final StreamController<PointerInputEvent> _controller;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) =>
      _MouseSurface(sink: _controller.sink, behavior: behavior, child: child);

  @override
  void dispose() => unawaited(_controller.close());
}

class _MouseSurface extends StatefulWidget {
  const _MouseSurface({
    required this.sink,
    required this.behavior,
    required this.child,
  });

  final EventSink<PointerInputEvent> sink;
  final HitTestBehavior behavior;
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

  void _emit(PointerInputEvent event) => widget.sink.add(event);

  void _onPointerHover(flutter_gestures.PointerHoverEvent e) =>
      _emit(CanvasHoverEvent(position: e.localPosition));

  void _onPointerSignal(flutter_gestures.PointerSignalEvent e) {
    if (e is flutter_gestures.PointerScrollEvent) {
      _emit(
        CanvasScrollEvent(
          position: e.localPosition,
          delta: e.scrollDelta,
        ),
      );
    }
  }

  void _onTapUp(TapUpDetails details) {
    _emit(CanvasTapEvent(position: details.localPosition));
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
      _emit(CanvasUpEvent(position: _dragLastPosition));
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
          behavior: widget.behavior,
          onTapUp: _onTapUp,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: widget.child,
        ),
      );
}
