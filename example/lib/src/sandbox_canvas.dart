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

  Offset? _cursorPosition;
  bool _isDown = false;
  bool _showCamera = false;
  String? _gestureError;

  @override
  void initState() {
    super.initState();
    _gestureSource = GestureInputSource(
      onError: (e, st) {
        debugPrint('GestureInputSource error: $e\n$st');
        if (mounted) setState(() => _gestureError = e.toString());
      },
    );
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
        setState(() {
          _cursorPosition = position;
          _isDown = true;
        });
        _tryStartDrag(_toCanvas(position));
      case CanvasMoveEvent(:final position):
        setState(() => _cursorPosition = position);
        _continueDrag(_toCanvas(position));
      case CanvasUpEvent() || CanvasTapEvent():
        setState(() => _isDown = false);
        _endDrag();
      case CanvasHoverEvent(:final position):
        setState(() => _cursorPosition = position);
      case CanvasScaleEvent(:final scaleDelta, :final panDelta):
        setState(() {
          _scale = (_scale * scaleDelta).clamp(0.25, 4.0);
          _canvasOffset += panDelta;
        });
      case CanvasScrollEvent(:final delta):
        setState(() => _canvasOffset -= delta * 0.5);
      case CanvasScaleEndEvent():
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
        child: Stack(
          children: [
            // Canvas
            ClipRect(
              child: CustomPaint(
                painter: _BoxesPainter(
                  boxes: _boxes,
                  offset: _canvasOffset,
                  scale: _scale,
                ),
                size: Size.infinite,
              ),
            ),

            // Hand / pointer cursor
            if (_cursorPosition != null)
              Positioned(
                left: _cursorPosition!.dx - 12,
                top: _cursorPosition!.dy - 12,
                child: IgnorePointer(
                  child: _AirCursor(isDown: _isDown),
                ),
              ),

            // Camera preview — bottom-right corner
            if (_showCamera)
              Positioned(
                right: 16,
                bottom: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _gestureSource.buildCameraPreview(
                    width: 240,
                    height: 180,
                  ),
                ),
              ),

            // Camera toggle button — top-right corner
            Positioned(
              right: 12,
              top: 12,
              child: _CameraToggle(
                active: _showCamera,
                onToggle: () => setState(() => _showCamera = !_showCamera),
              ),
            ),

            // Error banner — shown when GestureInputSource.initialize() fails
            if (_gestureError != null)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Material(
                  color: const Color(0xFFB71C1C),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hand tracking error: $_gestureError',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _gestureError = null),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ── Camera toggle button ──────────────────────────────────────────────────────

class _CameraToggle extends StatelessWidget {
  const _CameraToggle({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Material(
        color: active
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              active ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              size: 20,
              color: active ? Colors.black87 : Colors.white,
            ),
          ),
        ),
      );
}

// ── Air-pointer cursor ────────────────────────────────────────────────────────

class _AirCursor extends StatelessWidget {
  const _AirCursor({required this.isDown});

  final bool isDown;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(24, 24),
        painter: _AirCursorPainter(isDown: isDown),
      );
}

class _AirCursorPainter extends CustomPainter {
  const _AirCursorPainter({required this.isDown});

  final bool isDown;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final color = isDown ? Colors.redAccent : Colors.white;
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (isDown) {
      canvas.drawCircle(
        center,
        4,
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_AirCursorPainter old) => old.isDown != isDown;
}

// ── Canvas painter ────────────────────────────────────────────────────────────

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
