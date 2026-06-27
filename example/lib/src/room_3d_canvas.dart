import 'dart:async';
import 'dart:math' as math;

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

// ── 3-D vector ────────────────────────────────────────────────────────────────

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) =>
      _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V3 get normalized {
    final l = math.sqrt(x * x + y * y + z * z);
    return l < 1e-10 ? const _V3(0, 0, 1) : _V3(x / l, y / l, z / l);
  }
}

// ── Orbital camera ────────────────────────────────────────────────────────────

class _Cam {
  double az = 0.25;    // horizontal orbit angle (radians)
  double el = 0.42;   // vertical orbit angle (radians)
  double dist = 250.0; // distance from target

  static const _target = _V3(0, 55, 0);
  static const _fl = 680.0; // focal length (pixels)

  _V3 get pos {
    final ce = math.cos(el);
    return _V3(
      _target.x + dist * ce * math.sin(az),
      _target.y + dist * math.sin(el),
      _target.z + dist * ce * math.cos(az),
    );
  }

  _V3 get fwd => (_target - pos).normalized;
  _V3 get rgt => fwd.cross(const _V3(0, 1, 0)).normalized;
  _V3 get upV => rgt.cross(fwd);

  /// Projects a world point to screen, returns null if behind camera.
  Offset? project(_V3 w, Size sz) {
    final r = w - pos;
    final zc = r.dot(fwd);
    if (zc <= 10) return null;
    return Offset(
      r.dot(rgt) / zc * _fl + sz.width * 0.5,
      -r.dot(upV) / zc * _fl + sz.height * 0.5,
    );
  }

  double depthOf(_V3 w) => (w - pos).dot(fwd);

  void orbit(double dx, double dy) {
    az -= dx * 0.005;
    el = (el + dy * 0.005).clamp(-1.4, 1.4);
  }

  void zoomBy(double delta) => dist = (dist - delta * 1.5).clamp(200, 2200);
  void zoomFactor(double f) => dist = (dist / f.clamp(0.1, 10)).clamp(200, 2200);

  void snapAzimuth() {
    const h = math.pi / 2;
    az = (az / h).round() * h;
  }

  void reset() {
    az = 0.25;
    el = 0.42;
    dist = 250.0;
  }
}

// ── Mutable furniture box ─────────────────────────────────────────────────────

class _Box {
  _Box({
    required this.id,
    required this.label,
    required this.cx,
    required this.cz,
    required this.w,
    required this.h,
    required this.d,
    required this.color,
    this.selectable = true,
  });

  final int id;
  final String label;
  double cx, cz;       // floor-plane centre (XZ)
  double rotation = 0; // Y-axis rotation (radians)
  final double w, h, d;
  final Color color;
  final bool selectable;
  Rect screenBounds = Rect.zero; // updated each build for hit-testing
}

// ── Drawable face (painter's algorithm) ───────────────────────────────────────

class _Face implements Comparable<_Face> {
  const _Face(this.pts, this.color, this.depth);
  final List<Offset> pts;
  final Color color;
  final double depth;

  @override
  int compareTo(_Face other) => other.depth.compareTo(depth); // far → near
}

// ── Scene assembly ────────────────────────────────────────────────────────────

const _kHW = 300.0; // room half-width  (X)
const _kH  = 310.0; // room height      (Y)
const _kHD = 300.0; // room half-depth  (Z)

List<_Face> _buildScene(
    _Cam cam, List<_Box> boxes, int? selectedId, Size sz) {
  final faces = <_Face>[];

  void quad(List<_V3> verts, Color base, double shade) {
    final pts = <Offset>[];
    double sumD = 0;
    for (final v in verts) {
      final p = cam.project(v, sz);
      if (p == null) return; // any vertex clipped → skip face
      pts.add(p);
      sumD += cam.depthOf(v);
    }
    faces.add(_Face(
      pts,
      Color.lerp(Colors.black, base, shade)!,
      sumD / verts.length,
    ));
  }

  // ── Room shell ──────────────────────────────────────────────────────────

  // Floor — warm stone tiles
  quad([
    const _V3(-_kHW, 0, -_kHD), const _V3(_kHW, 0, -_kHD),
    const _V3(_kHW, 0, _kHD),   const _V3(-_kHW, 0, _kHD),
  ], const Color(0xFFCDC4B0), 1.0);

  // Back wall
  quad([
    const _V3(-_kHW, 0, _kHD),  const _V3(_kHW, 0, _kHD),
    const _V3(_kHW, _kH, _kHD), const _V3(-_kHW, _kH, _kHD),
  ], const Color(0xFFF2EBE0), 0.72);

  // Left wall
  quad([
    const _V3(-_kHW, 0, _kHD),   const _V3(-_kHW, 0, -_kHD),
    const _V3(-_kHW, _kH, -_kHD), const _V3(-_kHW, _kH, _kHD),
  ], const Color(0xFFEDE5D8), 0.65);

  // Right wall
  quad([
    const _V3(_kHW, 0, -_kHD),  const _V3(_kHW, 0, _kHD),
    const _V3(_kHW, _kH, _kHD), const _V3(_kHW, _kH, -_kHD),
  ], const Color(0xFFEDE5D8), 0.68);

  // Front wall (behind camera, often not visible but included for completeness)
  quad([
    const _V3(_kHW, 0, -_kHD),   const _V3(-_kHW, 0, -_kHD),
    const _V3(-_kHW, _kH, -_kHD), const _V3(_kHW, _kH, -_kHD),
  ], const Color(0xFFEDE5D8), 0.62);

  // Ceiling — dimmed so room feels lit from below
  quad([
    const _V3(-_kHW, _kH, -_kHD), const _V3(_kHW, _kH, -_kHD),
    const _V3(_kHW, _kH, _kHD),   const _V3(-_kHW, _kH, _kHD),
  ], const Color(0xFFDDD8D0), 0.55);

  // ── Furniture ───────────────────────────────────────────────────────────

  for (final b in boxes) {
    final sel = b.id == selectedId;
    final base = sel ? Color.lerp(b.color, Colors.lightBlueAccent, 0.4)! : b.color;
    final x = b.cx; final z = b.cz;
    final hw = b.w / 2; final hd = b.d / 2; final ht = b.h;
    final cr = math.cos(b.rotation);
    final sr = math.sin(b.rotation);
    // Rotate corner offset (dx, dz) around box centre then lift to height dy.
    _V3 c(double dx, double dy, double dz) =>
        _V3(x + dx * cr - dz * sr, dy, z + dx * sr + dz * cr);

    final blf = c(-hw, 0,  -hd);
    final brf = c( hw, 0,  -hd);
    final brb = c( hw, 0,   hd);
    final blb = c(-hw, 0,   hd);
    final tlf = c(-hw, ht, -hd);
    final trf = c( hw, ht, -hd);
    final trb = c( hw, ht,  hd);
    final tlb = c(-hw, ht,  hd);

    // 5 visible faces (skip bottom — hidden by floor)
    quad([tlb, trb, trf, tlf], base, sel ? 1.00 : 0.95); // top
    quad([blf, brf, trf, tlf], base, sel ? 0.92 : 0.82); // front
    quad([brb, blb, tlb, trb], base, sel ? 0.80 : 0.68); // back
    quad([blb, blf, tlf, tlb], base, sel ? 0.88 : 0.76); // left
    quad([brf, brb, trb, trf], base, sel ? 0.90 : 0.80); // right

    // Compute screen AABB for hit-testing (side effect is fine here)
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final v in [blf, brf, brb, blb, tlf, trf, trb, tlb]) {
      final p = cam.project(v, sz);
      if (p == null) continue;
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (minX.isFinite) {
      b.screenBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    }
  }

  faces.sort(); // painter's algorithm: far first
  return faces;
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _RoomPainter extends CustomPainter {
  const _RoomPainter({required this.faces, required this.labels});

  final List<_Face> faces;
  final List<({String text, Offset pos})> labels;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1C1917),
    );

    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = Colors.black.withValues(alpha: 0.18);

    for (final f in faces) {
      if (f.pts.length < 3) continue;
      final path = Path()..moveTo(f.pts[0].dx, f.pts[0].dy);
      for (var i = 1; i < f.pts.length; i++) {
        path.lineTo(f.pts[i].dx, f.pts[i].dy);
      }
      path.close();
      fill.color = f.color;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }

    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: l.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, l.pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RoomPainter old) => true;
}

// ── Widget ────────────────────────────────────────────────────────────────────

class Room3DCanvas extends StatefulWidget {
  const Room3DCanvas({super.key});

  @override
  State<Room3DCanvas> createState() => _Room3DState();
}

class _Room3DState extends State<Room3DCanvas> {
  late final CanvasInputController _controller;
  late final GestureInputSource _source;
  StreamSubscription<PointerInputEvent>? _sub;

  final _cam = _Cam();
  Size _sz = Size.zero;

  // Interaction state
  int? _selectedId;
  Offset? _cursor;
  bool _isDown = false;
  bool _showCamera = false;

  // Saved transform to restore on cancel
  double _savedCx = 0, _savedCz = 0, _savedRot = 0;
  Offset _prevDragPos = Offset.zero;

  final _boxes = <_Box>[
    // Rug (not selectable — just decoration)
    _Box(id: 0, label: '', cx: 0, cz: 75, w: 260, h: 5, d: 200, color: const Color(0xFF8B3A3A), selectable: false),
    // Sofa against back wall
    _Box(id: 1, label: 'Sofa', cx: 0, cz: 210, w: 200, h: 75, d: 70, color: const Color(0xFF4A5568)),
    // Coffee table
    _Box(id: 2, label: 'Table', cx: 0, cz: 90, w: 110, h: 38, d: 65, color: const Color(0xFF6B4C2A)),
    // Bookshelf — left corner
    _Box(id: 3, label: 'Shelf', cx: -240, cz: 235, w: 55, h: 195, d: 35, color: const Color(0xFF5C3D1E)),
    // Floor lamp
    _Box(id: 4, label: 'Lamp', cx: 215, cz: 195, w: 22, h: 155, d: 22, color: const Color(0xFFD4AF6B)),
    // Potted plant
    _Box(id: 5, label: 'Plant', cx: -215, cz: 120, w: 38, h: 75, d: 38, color: const Color(0xFF2D6A30)),
    // TV / display unit
    _Box(id: 6, label: 'TV', cx: 0, cz: -210, w: 160, h: 65, d: 40, color: const Color(0xFF2D3748)),
    // Side table
    _Box(id: 7, label: 'Side', cx: 200, cz: 90, w: 50, h: 45, d: 50, color: const Color(0xFF7C5E3A)),
  ];

  @override
  void initState() {
    super.initState();
    _source = GestureInputSource(
      onError: (e, _) => debugPrint('Room3D gesture error: $e'),
      pinchConfirmFrames: 2,
      swipeThreshold: 800,
    );
    _controller = CanvasInputController(
      sources: [MouseInputSource(), _source],
    );
    _sub = _controller.events.listen(_onEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sz = MediaQuery.sizeOf(context);
    _source.updateCanvasSize(_sz);
    unawaited(_source.initialize());
  }

  void _onEvent(PointerInputEvent ev) {
    switch (ev) {
      case CanvasDownEvent(:final position):
        setState(() {
          _cursor = position;
          _isDown = true;
          _prevDragPos = position;
          // Hit-test furniture (reverse order → topmost drawn first)
          _selectedId = null;
          for (final b in _boxes.reversed) {
            if (b.selectable && b.screenBounds.contains(position)) {
              _selectedId = b.id;
              _savedCx = b.cx;
              _savedCz = b.cz;
              _savedRot = b.rotation;
              break;
            }
          }
        });

      case CanvasMoveEvent(:final position):
        final delta = position - _prevDragPos;
        setState(() {
          _cursor = position;
          _prevDragPos = position;
          final sel =
              _selectedId == null ? null : _boxes.firstWhere((b) => b.id == _selectedId);
          if (sel != null) {
            // Map screen delta → world XZ using camera orientation + depth-based scale.
            final depth = _cam.depthOf(_V3(sel.cx, sel.h / 2, sel.cz));
            final s = depth / _Cam._fl;
            sel.cx = (sel.cx + delta.dx * _cam.rgt.x * s - delta.dy * _cam.fwd.x * s)
                .clamp(-_kHW + sel.w / 2, _kHW - sel.w / 2);
            sel.cz = (sel.cz + delta.dx * _cam.rgt.z * s - delta.dy * _cam.fwd.z * s)
                .clamp(-_kHD + sel.d / 2, _kHD - sel.d / 2);
          } else if (_isDown) {
            _cam.orbit(delta.dx, delta.dy);
          }
        });

      case CanvasUpEvent() || CanvasTapEvent():
        setState(() {
          _isDown = false;
          _selectedId = null;
        });

      case CanvasDoubleTapEvent():
        setState(() {
          _isDown = false;
          _selectedId = null;
          _cam.reset();
        });

      case CanvasCancelEvent():
        setState(() {
          _isDown = false;
          if (_selectedId != null) {
            final sel = _boxes.firstWhere((b) => b.id == _selectedId);
            sel.cx = _savedCx;
            sel.cz = _savedCz;
            sel.rotation = _savedRot;
          }
          _selectedId = null;
        });

      case CanvasHoverEvent(:final position):
        setState(() => _cursor = position);

      case CanvasScrollEvent(:final delta):
        setState(() {
          if (_selectedId != null && delta.dx != 0) {
            _boxes.firstWhere((b) => b.id == _selectedId).rotation +=
                delta.dx * 0.008;
          }
          _cam.zoomBy(delta.dy);
        });

      case CanvasScaleEvent(:final scaleDelta, :final rotation, :final panDelta):
        setState(() {
          _cam.zoomFactor(scaleDelta);
          if (_selectedId != null && rotation != 0) {
            _boxes.firstWhere((b) => b.id == _selectedId).rotation += rotation;
          } else {
            _cam.az -= rotation;
          }
          _cam.orbit(panDelta.dx * 0.2, panDelta.dy * 0.2);
        });

      case CanvasSwipeEvent(:final direction):
        setState(() {
          switch (direction) {
            case SwipeDirection.left:
              _cam.az += math.pi / 2;
            case SwipeDirection.right:
              _cam.az -= math.pi / 2;
            case SwipeDirection.up:
              _cam.el = (_cam.el + 0.35).clamp(-1.4, 1.4);
            case SwipeDirection.down:
              _cam.el = (_cam.el - 0.35).clamp(-1.4, 1.4);
          }
        });

      case CanvasGestureEvent():
      case CanvasScaleEndEvent():
      case CanvasLongPressEvent():
        break;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    if (sz != _sz) {
      // Update source outside of build cycle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _source.updateCanvasSize(sz);
        _sz = sz;
      });
    }

    final faces = _buildScene(_cam, _boxes, _selectedId, sz);

    final labels = <({String text, Offset pos})>[];
    for (final b in _boxes) {
      if (b.label.isEmpty) continue;
      final p = _cam.project(_V3(b.cx, b.h + 16, b.cz), sz);
      if (p != null) labels.add((text: b.label, pos: p));
    }

    final cursorColor = _selectedId != null
        ? Colors.lightBlueAccent
        : (_isDown ? Colors.redAccent : Colors.white);

    return _controller.buildSurface(
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RoomPainter(faces: faces, labels: labels),
                size: Size.infinite,
              ),
            ),
          ),

          // Camera feed preview
          if (_showCamera)
            Positioned(
              right: 16,
              bottom: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _source.buildCameraPreview(width: 200, height: 150),
              ),
            ),

          // Cursor ring
          if (_cursor != null)
            Positioned(
              left: _cursor!.dx - 10,
              top: _cursor!.dy - 10,
              child: IgnorePointer(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cursorColor, width: 2.5),
                    color: _isDown
                        ? cursorColor.withValues(alpha: 0.18)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),

          // Controls — top right
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                _CtrlBtn(
                  icon: _showCamera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  onTap: () => setState(() => _showCamera = !_showCamera),
                ),
                const SizedBox(height: 8),
                _CtrlBtn(
                  icon: Icons.home_rounded,
                  onTap: () => setState(_cam.reset),
                ),
              ],
            ),
          ),

          // Interaction hints — bottom left
          const Positioned(
            left: 12,
            bottom: 12,
            child: _HintsPanel(),
          ),
        ],
      ),
    );
  }
}

// ── UI helpers ────────────────────────────────────────────────────────────────

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({required this.icon, required this.onTap});
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

class _HintsPanel extends StatelessWidget {
  const _HintsPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const DefaultTextStyle(
          style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Drag empty space   — orbit camera'),
              Text('Scroll / pinch     — zoom in · out'),
              Text('Drag furniture     — move piece'),
              Text('H-scroll on piece  — rotate piece'),
              Text('Swipe ← →         — snap 90° view'),
              Text('Swipe ↑ ↓         — tilt camera'),
              Text('Double-tap         — reset view'),
            ],
          ),
        ),
      );
}
