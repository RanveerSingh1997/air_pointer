import 'dart:async';
import 'dart:math' as math;

import 'package:air_pointer/air_pointer.dart';
import 'package:air_pointer_example/src/calibration_screen.dart';
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
  StreamSubscription<GestureDebugInfo>? _debugSub;

  List<DraggableBox> _boxes = List.from(_initialBoxes);
  int? _draggingIndex;
  Offset _lastDragPosition = Offset.zero;
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;

  Offset? _cursorPosition;
  bool _isDown = false;
  GesturePhase _currentPhase = GesturePhase.lost;
  double _dwellProgress = 0.0;
  bool _showCamera = false;
  bool _showDebug = false;
  GestureDebugInfo? _debugInfo;
  String? _gestureError;

  @override
  void initState() {
    super.initState();
    _gestureSource = GestureInputSource(
      onError: (e, st) {
        debugPrint('GestureInputSource error: $e\n$st');
        if (mounted) setState(() => _gestureError = e.toString());
      },
      dwellDuration: const Duration(milliseconds: 800),
    );
    _controller = CanvasInputController(
      sources: [MouseInputSource(), _gestureSource],
    );
    _sub = _controller.events.listen(_onInput);
    _debugSub = _gestureSource.debugInfo.listen((info) {
      if (mounted) {
        setState(() {
          _currentPhase = info.phase;
          _dwellProgress = info.dwellProgress;
          if (_showDebug) _debugInfo = info;
        });
      }
    });
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
      case CanvasCancelEvent():
        // Cancel discards the in-progress drag without committing the move.
        setState(() => _isDown = false);
        _cancelDrag();
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

  // Derive cursor phase from event state + gesture phase for the overlay.
  // When dragging (_isDown), always show grab regardless of gesture phase.
  // For mouse input _currentPhase stays lost, which maps to hovering below.
  GesturePhase _effectivePhase() {
    if (_isDown) return GesturePhase.down;
    if (_currentPhase == GesturePhase.grace) return GesturePhase.grace;
    return GesturePhase.hovering;
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

  void _cancelDrag() {
    // Restore boxes to the state before the drag started by discarding the
    // in-progress index. We don't snapshot pre-drag state here, so we simply
    // stop dragging; a production app would roll back to a saved snapshot.
    setState(() => _draggingIndex = null);
  }

  @override
  void dispose() {
    unawaited(_debugSub?.cancel());
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

            // Debug overlay — hand skeleton + state info
            if (_showDebug && _debugInfo != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DebugOverlayPainter(info: _debugInfo!),
                  ),
                ),
              ),

            // Hand / pointer cursor (phase-aware)
            if (_cursorPosition != null)
              Positioned(
                left: _cursorPosition!.dx - 12,
                top: _cursorPosition!.dy - 12,
                child: IgnorePointer(
                  child: _AirCursor(
                    phase: _effectivePhase(),
                    dwellProgress: _dwellProgress,
                  ),
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

            // Tracking-lost hint — shown in camera mode when no hand detected.
            if (_showCamera &&
                _currentPhase == GesturePhase.lost &&
                _gestureError == null)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 220,
                child: Center(
                  child: _TrackingHint(),
                ),
              ),

            // Controls — top-right corner
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  _IconToggle(
                    active: _showDebug,
                    onToggle: () {
                      setState(() {
                        _showDebug = !_showDebug;
                        if (!_showDebug) _debugInfo = null;
                      });
                    },
                    iconOn: Icons.bug_report_rounded,
                    iconOff: Icons.bug_report_outlined,
                  ),
                  const SizedBox(width: 8),
                  _IconToggle(
                    active: _showCamera,
                    onToggle: () =>
                        setState(() => _showCamera = !_showCamera),
                    iconOn: Icons.videocam_rounded,
                    iconOff: Icons.videocam_off_rounded,
                  ),
                  const SizedBox(width: 8),
                  _IconAction(
                    icon: Icons.tune_rounded,
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          CalibrationDialog(source: _gestureSource),
                    ),
                  ),
                ],
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

// ── Tracking-lost hint ────────────────────────────────────────────────────────

class _TrackingHint extends StatelessWidget {
  const _TrackingHint();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Move your hand into view',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
}

// ── Icon toggle button (generic) ──────────────────────────────────────────────

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.active,
    required this.onToggle,
    required this.iconOn,
    required this.iconOff,
  });

  final bool active;
  final VoidCallback onToggle;
  final IconData iconOn;
  final IconData iconOff;

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
              active ? iconOn : iconOff,
              size: 20,
              color: active ? Colors.black87 : Colors.white,
            ),
          ),
        ),
      );
}

// ── Action button (non-toggle) ────────────────────────────────────────────────

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      );
}

// ── Air-pointer cursor ────────────────────────────────────────────────────────

class _AirCursor extends StatelessWidget {
  const _AirCursor({required this.phase, this.dwellProgress = 0.0});

  final GesturePhase phase;
  final double dwellProgress;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(24, 24),
        painter: _AirCursorPainter(phase: phase, dwellProgress: dwellProgress),
      );
}

class _AirCursorPainter extends CustomPainter {
  const _AirCursorPainter({required this.phase, this.dwellProgress = 0.0});

  final GesturePhase phase;
  final double dwellProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final (color, opacity, filled) = switch (phase) {
      GesturePhase.down => (Colors.redAccent, 0.9, true),
      GesturePhase.grace => (Colors.white, 0.35, false),
      _ => (Colors.white, 0.85, false),
    };

    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (filled) {
      canvas.drawCircle(
        center,
        4,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }

    // Dwell countdown ring: arc sweeps clockwise from 12-o'clock.
    if (dwellProgress > 0 && phase == GesturePhase.hovering) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 10),
        -math.pi / 2,
        dwellProgress * 2 * math.pi,
        false,
        Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_AirCursorPainter old) =>
      old.phase != phase || old.dwellProgress != dwellProgress;
}

// ── Debug overlay ─────────────────────────────────────────────────────────────

// MediaPipe hand landmark connectivity (21 points, 0-indexed).
const _kSkeleton = [
  // Thumb
  [0, 1], [1, 2], [2, 3], [3, 4],
  // Index
  [0, 5], [5, 6], [6, 7], [7, 8],
  // Middle
  [0, 9], [9, 10], [10, 11], [11, 12],
  // Ring
  [0, 13], [13, 14], [14, 15], [15, 16],
  // Pinky
  [0, 17], [17, 18], [18, 19], [19, 20],
  // Palm cross
  [5, 9], [9, 13], [13, 17],
];

class _DebugOverlayPainter extends CustomPainter {
  const _DebugOverlayPainter({required this.info});

  final GestureDebugInfo info;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirror x to match front-camera display.
    Offset toScreen(HandLandmarkPoint lm) =>
        Offset((1.0 - lm.x) * size.width, lm.y * size.height);

    void drawSkeleton(
      List<HandLandmarkPoint> lms,
      Color lineColor,
      Color dotColor,
    ) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      for (final bone in _kSkeleton) {
        canvas.drawLine(
          toScreen(lms[bone[0]]),
          toScreen(lms[bone[1]]),
          linePaint,
        );
      }

      final dotPaint = Paint()..style = PaintingStyle.fill;
      for (var i = 0; i < 21; i++) {
        final pos = toScreen(lms[i]);
        dotPaint.color = i == 4
            ? Colors.orangeAccent.withValues(alpha: 0.9)
            : i == 8
                ? Colors.lightBlueAccent.withValues(alpha: 0.9)
                : dotColor;
        canvas.drawCircle(pos, i == 4 || i == 8 ? 6 : 3, dotPaint);
      }
    }

    // Primary hand skeleton.
    if (info.landmarks.length == 21) {
      drawSkeleton(
        info.landmarks,
        Colors.white.withValues(alpha: 0.35),
        Colors.white.withValues(alpha: 0.6),
      );

      // Thumb–index connection coloured by pinch state.
      canvas.drawLine(
        toScreen(info.landmarks[4]),
        toScreen(info.landmarks[8]),
        Paint()
          ..color = info.phase == GesturePhase.down
              ? Colors.redAccent.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 2,
      );
    }

    // Second hand skeleton — green accent to distinguish from primary.
    if (info.isTwoHandActive && info.secondHandLandmarks.length == 21) {
      drawSkeleton(
        info.secondHandLandmarks,
        Colors.greenAccent.withValues(alpha: 0.35),
        Colors.greenAccent.withValues(alpha: 0.6),
      );
    }

    // Info panel — bottom-left corner.
    final phaseColor = switch (info.phase) {
      GesturePhase.down => Colors.redAccent,
      GesturePhase.hovering => Colors.greenAccent,
      GesturePhase.acquiring => Colors.amberAccent,
      GesturePhase.grace => Colors.orange,
      GesturePhase.lost => Colors.grey,
    };

    _drawInfoPanel(canvas, size, phaseColor);
  }

  void _drawInfoPanel(Canvas canvas, Size size, Color phaseColor) {
    const padding = 10.0;
    const lineH = 16.0;
    final bg = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final rowCount = info.isTwoHandActive ? 5.0 : 4.0;
    final panelRect = RRect.fromLTRBR(
      padding,
      size.height - padding - lineH * rowCount - 12,
      220,
      size.height - padding,
      const Radius.circular(6),
    );
    canvas.drawRRect(panelRect, bg);

    void drawLine(String text, double y, Color color) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padding + 6, y));
    }

    var y = panelRect.top + 6;
    drawLine('phase:   ${info.phase.name}', y, phaseColor);
    y += lineH;
    drawLine(
      'pinch:   ${info.pinchDistance.toStringAsFixed(3)}',
      y,
      Colors.white70,
    );
    y += lineH;
    if (info.isTwoHandActive) {
      drawLine('2-hand:  active', y, Colors.greenAccent);
      y += lineH;
    }
    drawLine(
      'worker:  ${info.workerLatencyMs.toStringAsFixed(1)} ms',
      y,
      Colors.white54,
    );
    y += lineH;
    drawLine('rtt:     ${info.roundTripMs} ms', y, Colors.white54);
    y += lineH;

    // Pinch distance bar: 0..0.15 range, markers at close/open thresholds.
    _drawPinchBar(canvas, Offset(padding + 6, y + 2), 198);
  }

  void _drawPinchBar(Canvas canvas, Offset origin, double width) {
    const barHeight = 6.0;
    const maxDist = 0.15;

    canvas.drawRRect(
      RRect.fromLTRBR(
        origin.dx,
        origin.dy,
        origin.dx + width,
        origin.dy + barHeight,
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );

    final filled = (math.min(info.pinchDistance, maxDist) / maxDist * width)
        .clamp(0, width)
        .toDouble();
    if (filled > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          origin.dx,
          origin.dy,
          origin.dx + filled,
          origin.dy + barHeight,
          const Radius.circular(3),
        ),
        Paint()
          ..color = info.phase == GesturePhase.down
              ? Colors.redAccent
              : Colors.greenAccent,
      );
    }

    // Threshold markers.
    void marker(double threshold, Color color) {
      final x = origin.dx + (threshold / maxDist * width).clamp(0, width);
      canvas.drawLine(
        Offset(x, origin.dy - 2),
        Offset(x, origin.dy + barHeight + 2),
        Paint()
          ..color = color
          ..strokeWidth = 1.5,
      );
    }

    marker(0.05, Colors.red.shade200);   // close threshold
    marker(0.08, Colors.green.shade200); // open threshold
  }

  @override
  bool shouldRepaint(_DebugOverlayPainter old) => old.info != info;
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
