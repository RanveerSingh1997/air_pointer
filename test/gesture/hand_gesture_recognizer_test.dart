import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_gesture_recognizer.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(800, 600);
const _dt = 1.0 / 30.0;

// 21 landmarks with all points at (0.5, 0.5, 0) except thumb tip [4] and
// index tip [8]. Distance between thumb and index is sqrt(dx²+dy²).
List<HandLandmarkPoint> _hand({
  double thumbX = 0.4,
  double thumbY = 0.5,
  double indexX = 0.6,
  double indexY = 0.5,
}) {
  final lms = List<HandLandmarkPoint>.generate(
    21,
    (_) => const HandLandmarkPoint(0.5, 0.5, 0),
  );
  lms[4] = HandLandmarkPoint(thumbX, thumbY, 0);
  lms[8] = HandLandmarkPoint(indexX, indexY, 0);
  return lms;
}

// Open hand: thumb–index distance = 0.2, well above open threshold (0.08).
List<HandLandmarkPoint> _open({double indexX = 0.5}) =>
    _hand(thumbX: indexX - 0.1, indexX: indexX);

// Pinched hand: thumb–index distance = 0.02, below close threshold (0.05).
List<HandLandmarkPoint> _pinch({double indexX = 0.5}) =>
    _hand(thumbX: indexX - 0.01, indexX: indexX);

// In hysteresis zone: distance = 0.06, above close (0.05) and below open (0.08).
List<HandLandmarkPoint> _hysteresis() =>
    _hand(thumbX: 0.47, indexX: 0.53);

// 21 landmarks with wrist at a specified position (for two-hand spread tests).
List<HandLandmarkPoint> _handAt(double wristX, double wristY) {
  final lms = List<HandLandmarkPoint>.generate(
    21,
    (_) => const HandLandmarkPoint(0.5, 0.5, 0),
  );
  lms[0] = HandLandmarkPoint(wristX, wristY, 0);          // wrist
  lms[4] = HandLandmarkPoint(wristX + 0.1, wristY, 0);   // thumb (open)
  lms[8] = HandLandmarkPoint(wristX + 0.15, wristY, 0);  // index tip
  return lms;
}

// Drive the recognizer through a sequence of frames; collect all events.
List<PointerInputEvent> _run(
  HandGestureRecognizer r,
  List<List<HandLandmarkPoint>?> frames,
) =>
    [
      for (final lms in frames)
        ...r.process(landmarks: lms, dt: _dt, canvasSize: _size).events,
    ];

// Advance past the 3-frame acquisition gate so tests start in hovering state.
HandGestureRecognizer _confirmed() {
  final r = HandGestureRecognizer();
  _run(r, [_open(), _open(), _open()]);
  assert(r.phase == GesturePhase.hovering, 'warmup failed');
  return r;
}

void main() {
  group('acquisition gate', () {
    test('no events during lost state', () {
      final r = HandGestureRecognizer();
      expect(_run(r, [null, null]), isEmpty);
      expect(r.phase, GesturePhase.lost);
    });

    test('no events for first acquireFrames-1 frames', () {
      final r = HandGestureRecognizer();
      final events = _run(r, [_open(), _open()]);
      expect(events, isEmpty);
      expect(r.phase, GesturePhase.acquiring);
    });

    test('confirms on acquireFrames-th consecutive frame, emits hover', () {
      final r = HandGestureRecognizer();
      final events = _run(r, [_open(), _open(), _open()]);
      expect(events.whereType<CanvasHoverEvent>(), isNotEmpty);
      expect(r.phase, GesturePhase.hovering);
    });

    test('interrupted acquisition resets counter', () {
      final r = HandGestureRecognizer();
      _run(r, [_open(), _open()]);         // 2 frames in
      _run(r, [null]);                     // interrupt
      final events = _run(r, [_open()]);   // only 1 new frame
      expect(events.whereType<CanvasHoverEvent>(), isEmpty);
      expect(r.phase, GesturePhase.acquiring);
    });
  });

  group('pinch hysteresis', () {
    test('close below pinchCloseThreshold emits CanvasDownEvent', () {
      final r = _confirmed();
      final events = _run(r, [_pinch()]);
      expect(events.single, isA<CanvasDownEvent>());
      expect(r.phase, GesturePhase.down);
    });

    test('open above pinchOpenThreshold emits CanvasUpEvent', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      final events = _run(r, [_open()]);
      expect(events.single, isA<CanvasUpEvent>());
      expect(r.phase, GesturePhase.hovering);
    });

    test('hysteresis zone from hovering does not trigger pinch', () {
      final r = _confirmed();
      final events = _run(r, [_hysteresis()]);
      expect(events.whereType<CanvasDownEvent>(), isEmpty);
      expect(r.phase, GesturePhase.hovering);
    });

    test('hysteresis zone from down does not release pinch', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      final events = _run(r, [_hysteresis()]);
      expect(events.whereType<CanvasUpEvent>(), isEmpty);
      expect(r.phase, GesturePhase.down);
    });
  });

  group('drag motion', () {
    test('move past deadzone emits CanvasMoveEvent', () {
      // deadzonePx=0 to avoid depending on filter convergence values.
      final r = HandGestureRecognizer(deadzonePx: 0);
      _run(r, [_open(), _open(), _open()]);  // confirm
      _run(r, [_pinch()]);                    // down at x=0.5
      // Index moves from 0.5 → 0.7: raw delta = 0.2 * 800 = 160 px >> deadzone.
      final events = _run(r, [_pinch(indexX: 0.7)]);
      expect(events.whereType<CanvasMoveEvent>(), isNotEmpty);
    });

    test('move within deadzone emits nothing', () {
      // Large deadzone so no real movement passes.
      final r = HandGestureRecognizer(deadzonePx: 1000);
      _run(r, [_open(), _open(), _open()]);
      _run(r, [_pinch()]);
      final events = _run(r, [_pinch(indexX: 0.501)]);
      expect(events.whereType<CanvasMoveEvent>(), isEmpty);
    });
  });

  group('hand exit (grace window)', () {
    test('hand exits during drag → CanvasCancelEvent, enters grace', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      final events = _run(r, [null]);
      expect(events.single, isA<CanvasCancelEvent>());
      expect(r.phase, GesturePhase.grace);
    });

    test('hand exits while hovering → grace, no cancel', () {
      final r = _confirmed();
      final events = _run(r, [null]);
      expect(events.whereType<CanvasCancelEvent>(), isEmpty);
      expect(r.phase, GesturePhase.grace);
    });

    test('grace window absorbs no-hand frames before expiry', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      _run(r, [null]);  // cancel + grace (graceCount=1)
      // graceFrames=5: 3 more nulls → graceCount=4, still grace.
      final events = _run(r, [null, null, null]);
      expect(events, isEmpty);
      expect(r.phase, GesturePhase.grace);
    });

    test('grace window expires → lost after graceFrames total', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      _run(r, [null]);              // graceCount=1
      _run(r, [null, null, null, null]);  // graceCount reaches 5 → lost
      expect(r.phase, GesturePhase.lost);
    });

    test('hand returns within grace → resumes hovering, no cancel', () {
      final r = _confirmed();
      _run(r, [null]);  // enter grace (from hovering, no cancel)
      final events = _run(r, [_open()]);
      expect(events.whereType<CanvasCancelEvent>(), isEmpty);
      expect(events.whereType<CanvasHoverEvent>(), isNotEmpty);
      expect(r.phase, GesturePhase.hovering);
    });
  });

  group('debug info', () {
    test('phase in debug matches recognizer phase', () {
      final r = HandGestureRecognizer();
      final result = r.process(landmarks: null, dt: _dt, canvasSize: _size);
      expect(result.debug.phase, r.phase);
    });

    test('landmarks in debug reflect passed input', () {
      final r = _confirmed();
      final lms = _open();
      final result = r.process(landmarks: lms, dt: _dt, canvasSize: _size);
      expect(result.debug.landmarks, same(lms));
    });

    test('landmarks empty when no hand passed', () {
      final r = HandGestureRecognizer();
      final result = r.process(landmarks: null, dt: _dt, canvasSize: _size);
      expect(result.debug.landmarks, isEmpty);
    });
  });

  group('clutch (Midas-touch guard)', () {
    test('closed hand at acquisition does not trigger pinch until reopened',
        () {
      final r = HandGestureRecognizer();
      // Confirm with closed hand (3 frames).
      _run(r, [_pinch(), _pinch(), _pinch()]);
      expect(r.phase, GesturePhase.hovering);

      // Pinch frames while mustOpenFirst is set — no down event.
      final events = _run(r, [_pinch(), _pinch()]);
      expect(events.whereType<CanvasDownEvent>(), isEmpty);
      expect(r.phase, GesturePhase.hovering);

      // Open hand — clears the guard.
      _run(r, [_open()]);

      // Now pinch should fire.
      final events2 = _run(r, [_pinch()]);
      expect(events2.whereType<CanvasDownEvent>(), isNotEmpty);
      expect(r.phase, GesturePhase.down);
    });

    test('open hand at acquisition clears guard on the same frame', () {
      final r = HandGestureRecognizer();
      // Confirm with open hand — guard should be cleared immediately.
      _run(r, [_open(), _open(), _open()]);

      // First pinch should work without an extra open frame.
      final events = _run(r, [_pinch()]);
      expect(events.whereType<CanvasDownEvent>(), isNotEmpty);
    });

    test('guard re-applied after two-hand mode exits', () {
      final r = _confirmed();
      // Enter and exit two-hand mode.
      r.process(
        landmarks: _handAt(0.3, 0.5),
        secondHandLandmarks: _handAt(0.7, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      // Return to single-hand while pinching — should NOT fire.
      final result = r.process(
        landmarks: _pinch(),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.events.whereType<CanvasDownEvent>(), isEmpty);
    });
  });

  group('two-hand scale', () {
    test('second hand appearing mid-drag emits cancel before scale baseline',
        () {
      final r = _confirmed();
      _run(r, [_pinch()]);  // enter drag
      expect(r.phase, GesturePhase.down);

      // Second hand appears.
      final result = r.process(
        landmarks: _pinch(),
        secondHandLandmarks: _handAt(0.7, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.events.first, isA<CanvasCancelEvent>());
      expect(r.phase, GesturePhase.hovering);
    });

    test('scale event emitted from second two-hand frame', () {
      final r = HandGestureRecognizer();
      // Frame 1: baseline — hands close together.
      r.process(
        landmarks: _handAt(0.35, 0.5),
        secondHandLandmarks: _handAt(0.65, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      // Frame 2: hands spread apart.
      final result = r.process(
        landmarks: _handAt(0.2, 0.5),
        secondHandLandmarks: _handAt(0.8, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      final scales = result.events.whereType<CanvasScaleEvent>();
      expect(scales, isNotEmpty);
      expect(scales.first.scaleDelta, greaterThan(1.0));  // zoom in
    });

    test('second hand disappearing emits CanvasScaleEndEvent', () {
      final r = HandGestureRecognizer();
      // Establish two-hand mode.
      r.process(
        landmarks: _handAt(0.35, 0.5),
        secondHandLandmarks: _handAt(0.65, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      r.process(
        landmarks: _handAt(0.25, 0.5),
        secondHandLandmarks: _handAt(0.75, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      // Second hand leaves.
      final result = r.process(
        landmarks: _handAt(0.35, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.events.first, isA<CanvasScaleEndEvent>());
    });

    test('debug info reflects two-hand state', () {
      final r = HandGestureRecognizer();
      final result = r.process(
        landmarks: _handAt(0.35, 0.5),
        secondHandLandmarks: _handAt(0.65, 0.5),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.debug.isTwoHandActive, isTrue);
      expect(result.debug.secondHandLandmarks, isNotEmpty);
    });
  });

  group('reset', () {
    test('reset returns recognizer to lost state', () {
      final r = _confirmed();
      _run(r, [_pinch()]);
      r.reset();
      expect(r.phase, GesturePhase.lost);
    });

    test('after reset, acquisition restarts from zero', () {
      final r = _confirmed();
      r.reset();
      // Only 2 frames — not yet confirmed.
      final events = _run(r, [_open(), _open()]);
      expect(events.whereType<CanvasHoverEvent>(), isEmpty);
    });
  });

  group('dwell-click', () {
    // Build a confirmed recognizer with dwell enabled.
    HandGestureRecognizer dwellR({
      Duration duration = const Duration(milliseconds: 600),
      double radius = 5.0,
    }) {
      final r = HandGestureRecognizer(
        dwellDuration: duration,
        dwellRadius: radius,
      );
      _run(r, [_open(), _open(), _open()]);
      assert(r.phase == GesturePhase.hovering);
      return r;
    }

    // At 30fps, 600ms = 18 frames to accumulate the dwell threshold.
    const kDwellFrames = 18;

    test('fires CanvasTapEvent after dwellDuration of stillness', () {
      final r = dwellR();
      // 3 acquisition frames already ran in _dwellR. The anchor reset to the
      // first hover position on frame 3. 18 more frames at the same position
      // accumulate exactly 600ms.
      final events = _run(r, List.filled(kDwellFrames, _open()));
      expect(events.whereType<CanvasTapEvent>(), hasLength(1));
    });

    test('no tap before dwellDuration elapses', () {
      final r = dwellR();
      final events = _run(r, List.filled(kDwellFrames - 1, _open()));
      expect(events.whereType<CanvasTapEvent>(), isEmpty);
    });

    test('movement beyond radius resets dwell timer', () {
      final r = dwellR();
      // Nearly complete a dwell at position A (17 of 18 frames needed).
      _run(r, List.filled(kDwellFrames - 1, _open()));
      // Move ~80px to position B — resets timer.
      _run(r, [_open(indexX: 0.4)]);
      // Only 5 more frames at B — far short of a full dwell from the reset.
      final events = _run(r, List.filled(5, _open(indexX: 0.4)));
      expect(events.whereType<CanvasTapEvent>(), isEmpty);
    });

    test('dwell does not fire during pinch-down phase', () {
      final r = dwellR();
      final events = _run(r, [
        _pinch(),
        ...List.filled(kDwellFrames + 10, _pinch()),
        _open(),
      ]);
      expect(events.whereType<CanvasTapEvent>(), isEmpty);
      expect(events.whereType<CanvasDownEvent>(), hasLength(1));
      expect(events.whereType<CanvasUpEvent>(), hasLength(1));
    });

    test('dwellProgress is 0.0 when dwell is disabled', () {
      final r = _confirmed();  // default dwellDuration = Duration.zero
      final result = r.process(landmarks: _open(), dt: _dt, canvasSize: _size);
      expect(result.debug.dwellProgress, 0.0);
    });

    test('dwellProgress is 0.0 immediately after tap fires', () {
      final r = dwellR();
      _run(r, List.filled(kDwellFrames, _open()));
      // Next frame: mustMoveBeforeDwell=true → progress resets to 0.
      final result = r.process(landmarks: _open(), dt: _dt, canvasSize: _size);
      expect(result.debug.dwellProgress, 0.0);
    });

    test('second tap requires cursor movement after first', () {
      final r = dwellR();
      _run(r, List.filled(kDwellFrames, _open()));
      // Holding still at same position — no second tap.
      final events1 = _run(r, List.filled(kDwellFrames + 5, _open()));
      expect(events1.whereType<CanvasTapEvent>(), isEmpty);
      // Move past radius, then hold still. The OneEuroFilter takes ~20 frames to
      // converge after an 80px jump, so provide kDwellFrames * 4 frames of margin.
      final events2 = _run(r, [
        _open(indexX: 0.4),
        ...List.filled(kDwellFrames * 4, _open(indexX: 0.4)),
      ]);
      expect(events2.whereType<CanvasTapEvent>(), hasLength(1));
    });

    test('dwell resets when hand exits frame', () {
      final r = dwellR();
      // Accumulate half the required dwell.
      _run(r, List.filled(kDwellFrames ~/ 2, _open()));
      // Hand exits — dwell elapsed resets to 0.
      r.process(landmarks: null, dt: _dt, canvasSize: _size);
      // Re-acquire (3 frames).
      _run(r, [_open(), _open(), _open()]);
      // Another half-dwell: total since last reset is well under a full dwell.
      final events = _run(r, List.filled(kDwellFrames ~/ 2, _open()));
      expect(events.whereType<CanvasTapEvent>(), isEmpty);
    });
  });
}
