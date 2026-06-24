import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Input source for stylus devices — Apple Pencil, Samsung S-Pen, and any
/// device that reports [PointerDeviceKind.stylus] or
/// [PointerDeviceKind.invertedStylus] events.
///
/// Maps stylus contact to element-drag canvas events:
///
/// | Contact | Events |
/// |---|---|
/// | Pen tip down | [CanvasDownEvent] (with [CanvasDownEvent.pressure]) |
/// | Pen tip move | [CanvasMoveEvent] (with [CanvasMoveEvent.pressure]) |
/// | Pen tip up — minimal movement | [CanvasTapEvent] |
/// | Pen tip up — after drag | [CanvasUpEvent] |
/// | Two taps within [doubleTapWindow] | [CanvasTapEvent] + [CanvasDoubleTapEvent] |
/// | Pen hover (proximity) | [CanvasHoverEvent] |
/// | OS pointer cancel | [CanvasCancelEvent] |
///
/// Mouse, touch, and trackpad events are silently filtered so this source can
/// be combined with [MouseInputSource] or [TouchInputSource] in a
/// [CanvasInputController] without emitting duplicate events.
///
/// **Pressure** — [CanvasDownEvent.pressure] and [CanvasMoveEvent.pressure]
/// carry the hardware value (0.0–1.0). Consumers that do not need
/// pressure-sensitive rendering can ignore the field; it defaults to 1.0 from
/// all other input sources.
///
/// **Eraser detection** — listen to [eraserModeStream] to distinguish the pen
/// tip ([PointerDeviceKind.stylus]) from the eraser end
/// ([PointerDeviceKind.invertedStylus]). The stream only emits on mode changes,
/// not every frame.
final class StylusInputSource implements CanvasInputSource {
  StylusInputSource({
    this.behavior = HitTestBehavior.translucent,
    this.tapSlop = 8.0,
    this.doubleTapWindow = const Duration(milliseconds: 300),
  })  : _controller = StreamController.broadcast(),
        _eraserController = StreamController<bool>.broadcast();

  final HitTestBehavior behavior;

  /// Maximum displacement (logical pixels) between pen-down and pen-up that is
  /// still treated as a tap.
  final double tapSlop;

  /// Maximum interval between two pen taps that qualifies as a double-tap.
  final Duration doubleTapWindow;

  final StreamController<PointerInputEvent> _controller;
  final StreamController<bool> _eraserController;

  /// Emits `true` when the eraser end ([PointerDeviceKind.invertedStylus]) is
  /// in contact or proximity; `false` when the pen tip is active.
  ///
  /// Only emits on mode changes — consecutive pen-tip contacts emit `false`
  /// only once. Consumers can listen and toggle a flag without de-duplication.
  Stream<bool> get eraserModeStream => _eraserController.stream;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => _StylusSurface(
        eventSink: _controller.sink,
        eraserSink: _eraserController.sink,
        behavior: behavior,
        tapSlop: tapSlop,
        doubleTapWindow: doubleTapWindow,
        child: child,
      );

  @override
  void dispose() {
    unawaited(_controller.close());
    unawaited(_eraserController.close());
  }
}

class _StylusSurface extends StatefulWidget {
  const _StylusSurface({
    required this.eventSink,
    required this.eraserSink,
    required this.behavior,
    required this.tapSlop,
    required this.doubleTapWindow,
    required this.child,
  });

  final EventSink<PointerInputEvent> eventSink;
  final EventSink<bool> eraserSink;
  final HitTestBehavior behavior;
  final double tapSlop;
  final Duration doubleTapWindow;
  final Widget child;

  @override
  State<_StylusSurface> createState() => _StylusSurfaceState();
}

class _StylusSurfaceState extends State<_StylusSurface> {
  int? _activePointer; // pointer ID of the tracked stylus contact
  Offset _downPosition = Offset.zero;
  bool _tapPending = false;
  DateTime? _lastTapTime;
  bool? _lastEraserMode; // null = never emitted

  static bool _isStylusKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _emit(PointerInputEvent event) => widget.eventSink.add(event);

  void _updateEraserMode(PointerDeviceKind kind) {
    final isEraser = kind == PointerDeviceKind.invertedStylus;
    if (isEraser != _lastEraserMode) {
      _lastEraserMode = isEraser;
      widget.eraserSink.add(isEraser);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!_isStylusKind(e.kind)) return;
    _activePointer ??= e.pointer;
    if (e.pointer != _activePointer) return;
    _updateEraserMode(e.kind);
    _downPosition = e.localPosition;
    _tapPending = true;
    _emit(CanvasDownEvent(position: e.localPosition, pressure: e.pressure));
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    _emit(CanvasMoveEvent(position: e.localPosition, pressure: e.pressure));
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    if (_tapPending) {
      _tapPending = false;
      final dist = (e.localPosition - _downPosition).distance;
      if (dist < widget.tapSlop) {
        _emitTap();
        return;
      }
    }
    _emit(CanvasUpEvent(position: e.localPosition));
  }

  void _onPointerHover(PointerHoverEvent e) {
    if (!_isStylusKind(e.kind)) return;
    _updateEraserMode(e.kind);
    _emit(CanvasHoverEvent(position: e.localPosition));
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _tapPending = false;
    _emit(const CanvasCancelEvent());
  }

  void _emitTap() {
    final now = DateTime.now();
    final isDouble = _lastTapTime != null &&
        now.difference(_lastTapTime!) <= widget.doubleTapWindow;
    _emit(CanvasTapEvent(position: _downPosition));
    if (isDouble) {
      _emit(CanvasDoubleTapEvent(position: _downPosition));
      _lastTapTime = null;
    } else {
      _lastTapTime = now;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: widget.behavior,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerCancel: _onPointerCancel,
        child: widget.child,
      );
}
