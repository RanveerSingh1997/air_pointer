import 'package:flutter/painting.dart';

sealed class PointerInputEvent {
  const PointerInputEvent();
}

final class CanvasTapEvent extends PointerInputEvent {
  const CanvasTapEvent({required this.position});

  final Offset position;
}

final class CanvasDownEvent extends PointerInputEvent {
  const CanvasDownEvent({required this.position});

  final Offset position;
}

final class CanvasMoveEvent extends PointerInputEvent {
  const CanvasMoveEvent({required this.position});

  final Offset position;
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
  const CanvasScrollEvent({required this.position, required this.delta});

  final Offset position;
  final Offset delta;
}

final class CanvasScaleEvent extends PointerInputEvent {
  const CanvasScaleEvent({
    required this.focalPoint,
    required this.scaleDelta,
    required this.panDelta,
  });

  final Offset focalPoint;

  /// Multiplicative scale factor: 1.05 = 5% zoom in, 0.95 = 5% zoom out.
  final double scaleDelta;
  final Offset panDelta;
}

final class CanvasScaleEndEvent extends PointerInputEvent {
  const CanvasScaleEndEvent();
}
