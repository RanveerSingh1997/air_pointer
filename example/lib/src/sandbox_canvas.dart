import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:air_pointer_example/src/draggable_box.dart';
import 'package:flutter/material.dart';

final _initialBoxes = [
  DraggableBox(
    rect: const Rect.fromLTWH(80, 80, 160, 100),
    color: Colors.blue.shade300,
  ),
  DraggableBox(
    rect: const Rect.fromLTWH(320, 200, 160, 100),
    color: Colors.green.shade300,
  ),
  DraggableBox(
    rect: const Rect.fromLTWH(560, 120, 160, 100),
    color: Colors.orange.shade300,
  ),
];

class SandboxCanvas extends StatefulWidget {
  const SandboxCanvas({super.key});

  @override
  State<SandboxCanvas> createState() => _SandboxCanvasState();
}

class _SandboxCanvasState extends State<SandboxCanvas> {
  late final CanvasInputController _controller;
  late final StreamSubscription<PointerInputEvent> _sub;
  late final GestureInputSource _gestureSource;

  List<DraggableBox> _boxes = List.from(_initialBoxes);
  int? _draggingIndex;
  Offset _lastDragPosition = Offset.zero;
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _gestureSource = GestureInputSource();
    _controller = CanvasInputController(
      sources: [MouseInputSource(), _gestureSource],
    );
    _sub = _controller.events.listen(_onInput);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _gestureSource.updateCanvasSize(size);
    unawaited(_gestureSource.initialize());
  }

  void _onInput(PointerInputEvent event) {
    switch (event) {
      case CanvasDownEvent(:final position):
        _tryStartDrag(_toCanvas(position));
      case CanvasMoveEvent(:final position):
        _continueDrag(_toCanvas(position));
      case CanvasUpEvent() || CanvasTapEvent():
        _endDrag();
      case CanvasScaleEvent(:final scaleDelta, :final panDelta):
        setState(() {
          _scale = (_scale * scaleDelta).clamp(0.25, 4.0);
          _canvasOffset += panDelta;
        });
      case CanvasScrollEvent(:final delta):
        setState(() => _canvasOffset -= delta * 0.5);
      case CanvasScaleEndEvent() || CanvasHoverEvent():
        break;
    }
  }

  Offset _toCanvas(Offset screen) => (screen - _canvasOffset) / _scale;

  void _tryStartDrag(Offset canvasPoint) {
    for (var i = _boxes.length - 1; i >= 0; i--) {
      if (_boxes[i].contains(canvasPoint)) {
        setState(() {
          _draggingIndex = i;
          _lastDragPosition = canvasPoint;
        });
        return;
      }
    }
  }

  void _continueDrag(Offset canvasPoint) {
    final idx = _draggingIndex;
    if (idx == null) return;
    final delta = canvasPoint - _lastDragPosition;
    setState(() {
      _boxes = [
        for (var i = 0; i < _boxes.length; i++)
          i == idx ? _boxes[i].shifted(delta) : _boxes[i],
      ];
      _lastDragPosition = canvasPoint;
    });
  }

  void _endDrag() => setState(() => _draggingIndex = null);

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller.buildSurface(
        child: ClipRect(
          child: CustomPaint(
            painter: _BoxesPainter(
              boxes: _boxes,
              offset: _canvasOffset,
              scale: _scale,
            ),
            size: Size.infinite,
          ),
        ),
      );
}

class _BoxesPainter extends CustomPainter {
  const _BoxesPainter({
    required this.boxes,
    required this.offset,
    required this.scale,
  });

  final List<DraggableBox> boxes;
  final Offset offset;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    for (final box in boxes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.rect, const Radius.circular(8)),
        Paint()..color = box.color,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.rect, const Radius.circular(8)),
        Paint()
          ..color = box.color.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoxesPainter old) =>
      old.boxes != boxes || old.offset != offset || old.scale != scale;
}
