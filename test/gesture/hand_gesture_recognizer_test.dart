import 'dart:math' as math;

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

    test('custom tight close threshold (0.03) still triggers on _pinch()', () {
      final r = HandGestureRecognizer(
        pinchCloseThreshold: 0.03,
        pinchOpenThreshold: 0.06,
      );
      _run(r, [_open(), _open(), _open()]);
      // _pinch() has distance 0.02 < 0.03.
      final events = _run(r, [_pinch()]);
      expect(events.single, isA<CanvasDownEvent>());
    });

    test('distance in default zone (0.04) triggers at default threshold but '
        'not at tighter threshold (0.03)', () {
      // Distance = 0.04 → thumb at 0.48, index at 0.52.
      final tightPinch = _hand(thumbX: 0.48, indexX: 0.52);

      // Default close=0.05: 0.04 < 0.05 → triggers.
      final r1 = HandGestureRecognizer();
      _run(r1, [_open(), _open(), _open()]);
      expect(
        _run(r1, [tightPinch]).whereType<CanvasDownEvent>(),
        isNotEmpty,
      );

      // Tight close=0.03: 0.04 > 0.03 → does NOT trigger.
      final r2 = HandGestureRecognizer(
        pinchCloseThreshold: 0.03,
        pinchOpenThreshold: 0.06,
      );
      _run(r2, [_open(), _open(), _open()]);
      expect(
        _run(r2, [tightPinch]).whereType<CanvasDownEvent>(),
        isEmpty,
      );
    });
  });

  group('pinchConfirmFrames', () {
    test('default (1 frame) triggers on the first pinch frame', () {
      final r = HandGestureRecognizer(); // pinchConfirmFrames defaults to 1
      _run(r, [_open(), _open(), _open()]);
      final events = _run(r, [_pinch()]);
      expect(events.single, isA<CanvasDownEvent>());
      expect(r.phase, GesturePhase.down);
    });

    test('confirmFrames=2: first pinch frame emits hover, not down', () {
      final r = HandGestureRecognizer(pinchConfirmFrames: 2);
      _run(r, [_open(), _open(), _open()]);
      final events = _run(r, [_pinch()]);
      expect(events.whereType<CanvasDownEvent>(), isEmpty);
      expect(events.whereType<CanvasHoverEvent>(), isNotEmpty);
      expect(r.phase, GesturePhase.hovering);
    });

    test('confirmFrames=2: second consecutive pinch frame emits CanvasDownEvent', () {
      final r = HandGestureRecognizer(pinchConfirmFrames: 2);
      _run(r, [_open(), _open(), _open()]);
      _run(r, [_pinch()]);                  // frame 1 — confirm count = 1
      final events = _run(r, [_pinch()]);   // frame 2 — confirmed
      expect(events.single, isA<CanvasDownEvent>());
      expect(r.phase, GesturePhase.down);
    });

    test('confirm count resets when hand opens between pinch frames', () {
      final r = HandGestureRecognizer(pinchConfirmFrames: 2);
      _run(r, [_open(), _open(), _open()]);
      _run(r, [_pinch()]);   // count = 1
      _run(r, [_open()]);    // hand opens — count resets to 0
      final events = _run(r, [_pinch()]);  // count = 1 again, not 2
      expect(events.whereType<CanvasDownEvent>(), isEmpty);
      expect(r.phase, GesturePhase.hovering);
    });

    test('confirm count resets when hand exits and re-acquires', () {
      final r = HandGestureRecognizer(pinchConfirmFrames: 2);
      _run(r, [_open(), _open(), _open()]);
      _run(r, [_pinch()]);            // count = 1
      _run(r, [null]);                // hand exits — count resets
      _run(r, [_open(), _open(), _open()]);  // re-acquire
      final events = _run(r, [_pinch()]);  // count = 1, not 2
      expect(events.whereType<CanvasDownEvent>(), isEmpty);
      expect(r.phase, GesturePhase.hovering);
    });

    test('confirmFrames=3: three consecutive pinch frames required', () {
      final r = HandGestureRecognizer(pinchConfirmFrames: 3);
      _run(r, [_open(), _open(), _open()]);
      expect(
        _run(r, [_pinch()]).whereType<CanvasDownEvent>(),
        isEmpty,
        reason: 'frame 1 of 3',
      );
      expect(
        _run(r, [_pinch()]).whereType<CanvasDownEvent>(),
        isEmpty,
        reason: 'frame 2 of 3',
      );
      final events = _run(r, [_pinch()]);
      expect(events.single, isA<CanvasDownEvent>(), reason: 'frame 3 of 3');
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

  group('pointing-finger scroll', () {
    // Pointing hand: index tip above indexPip (y=0.3 < 0.5), middle tip below
    // middlePip (y=0.7 > 0.5), thumb open (distance ≈ 0.22 >> 0.08 threshold).
    List<HandLandmarkPoint> pointing({double indexY = 0.3}) {
      final lms = List<HandLandmarkPoint>.generate(
        21,
        (_) => const HandLandmarkPoint(0.5, 0.5, 0),
      );
      lms[4] = const HandLandmarkPoint(0.4, 0.5, 0);  // thumb tip — open
      lms[8] = HandLandmarkPoint(0.5, indexY, 0);      // index tip — above PIP (extended)
      lms[12] = const HandLandmarkPoint(0.5, 0.7, 0); // middle tip — below PIP (curled)
      lms[20] = const HandLandmarkPoint(0.5, 0.7, 0); // pinky tip — below PIP (curled, not gun gesture)
      return lms;
    }

    // Confirmed recognizer with scroll enabled.
    HandGestureRecognizer scrollR() {
      final r = HandGestureRecognizer(scrollEnabled: true);
      _run(r, [_open(), _open(), _open()]);
      assert(r.phase == GesturePhase.hovering);
      return r;
    }

    test('no scroll events when scrollEnabled is false', () {
      final r = _confirmed();  // scrollEnabled defaults to false
      final events = _run(r, List.filled(10, pointing()));
      expect(events.whereType<CanvasScrollEvent>(), isEmpty);
    });

    test('first pointing frame emits hover not scroll', () {
      final r = scrollR();
      final result = r.process(
        landmarks: pointing(),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.events, hasLength(1));
      expect(result.events.first, isA<CanvasHoverEvent>());
    });

    test('subsequent pointing frames emit CanvasScrollEvent', () {
      final r = scrollR();
      _run(r, [pointing()]);  // consume first frame (hover)
      final events = _run(r, List.filled(5, pointing()));
      expect(events.whereType<CanvasScrollEvent>(), hasLength(5));
      expect(events.whereType<CanvasHoverEvent>(), isEmpty);
    });

    test('scroll delta.dy is positive when finger moves down', () {
      final r = scrollR();
      // Settle filter at upper position (indexY=0.2 → canvas y≈120px).
      // Both positions must stay < indexPip y (0.5) to keep pointing active.
      _run(r, List.filled(60, pointing(indexY: 0.2)));
      // Move finger down (indexY=0.4 → canvas y≈240px → dy > 0).
      final events = _run(r, List.filled(10, pointing(indexY: 0.4)));
      final scrolls = events.whereType<CanvasScrollEvent>().toList();
      expect(scrolls, isNotEmpty);
      expect(scrolls.any((e) => e.delta.dy > 0), isTrue);
    });

    test('no scroll when middle finger is extended (not pointing)', () {
      final r = scrollR();
      _run(r, [pointing()]);  // establish pointing baseline
      // Switch to open hand (both index and middle extended).
      final events = _run(r, List.filled(5, _open()));
      expect(events.whereType<CanvasScrollEvent>(), isEmpty);
    });

    test('scroll stops during pinch-down and does not resume mid-drag', () {
      final r = scrollR();
      _run(r, [pointing()]);          // baseline
      _run(r, List.filled(5, pointing()));  // scroll active
      // Pinch: should cancel scroll and emit CanvasDownEvent.
      final events = _run(r, [_pinch(), ...List.filled(5, _pinch())]);
      expect(events.whereType<CanvasScrollEvent>(), isEmpty);
      expect(events.whereType<CanvasDownEvent>(), hasLength(1));
    });

    test('isPointing debug flag is true while pointing', () {
      final r = scrollR();
      r.process(landmarks: pointing(), dt: _dt, canvasSize: _size); // first frame: baseline
      final result = r.process(
        landmarks: pointing(),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.debug.isPointing, isTrue);
    });

    test('isPointing debug flag is false when not pointing', () {
      final r = scrollR();
      final result = r.process(
        landmarks: _open(),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.debug.isPointing, isFalse);
    });

    test('isPointing is false when scrollEnabled is false', () {
      final r = _confirmed();
      final result = r.process(
        landmarks: pointing(),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.debug.isPointing, isFalse);
    });

    test('scroll resets on hand exit — no delta jump on re-entry', () {
      final r = scrollR();
      // Establish pointing at indexY=0.3 (~180 px screen) for 30 frames.
      _run(r, List.filled(30, pointing()));
      // Hand exits — _prevScrollPosition must be cleared.
      _run(r, [null, null, null, null, null]);
      // Re-acquire: 2 open-hand frames drive the acquisition counter.
      _run(r, [_open(), _open()]);
      // Third acquisition frame is also the first pointing frame at a shifted
      // position (0.4 vs prior 0.3). Without the reset this would emit a scroll
      // jump of ~60 px * scrollScale. With the reset it must be a hover baseline.
      final result = r.process(
        landmarks: pointing(indexY: 0.4),
        dt: _dt,
        canvasSize: _size,
      );
      expect(result.events.first, isA<CanvasHoverEvent>());
    });
  });

  group('velocity prediction', () {
    // Helper: advance a confirmed recognizer through N frames with a moving
    // index finger and return the last hover position.
    Offset driveMoving(HandGestureRecognizer r, {required int frames}) {
      for (var i = 0; i < frames; i++) {
        final x = 0.6 - i * 0.01;  // decreasing index.x → mirrored screen-x increases
        r.process(
          landmarks: _open(indexX: x.clamp(0.0, 1.0)),
          dt: _dt,
          canvasSize: _size,
        );
      }
      final last = r.process(
        landmarks: _open(indexX: (0.6 - frames * 0.01).clamp(0.0, 1.0)),
        dt: _dt,
        canvasSize: _size,
      );
      return (last.events.whereType<CanvasHoverEvent>().first).position;
    }

    test('zero prediction horizon — position identical to unaugmented output', () {
      // With no motion (static landmarks), a 50ms-prediction recognizer and a
      // default recognizer should converge to the same position because velocity ≈ 0.
      final rBase = _confirmed();
      final rPred = HandGestureRecognizer(
        predictionHorizon: const Duration(milliseconds: 50),
      );
      _run(rPred, [_open(), _open(), _open()]);

      // 30 static frames — both filters settle; velocity → 0.
      for (var i = 0; i < 30; i++) {
        rBase.process(landmarks: _open(), dt: _dt, canvasSize: _size);
        rPred.process(landmarks: _open(), dt: _dt, canvasSize: _size);
      }
      final baseResult =
          rBase.process(landmarks: _open(), dt: _dt, canvasSize: _size);
      final predResult =
          rPred.process(landmarks: _open(), dt: _dt, canvasSize: _size);

      final basePos = baseResult.events.whereType<CanvasHoverEvent>().first.position;
      final predPos = predResult.events.whereType<CanvasHoverEvent>().first.position;
      // Static signal → zero velocity → prediction adds nothing.
      expect(predPos.dx, closeTo(basePos.dx, 1.0));
      expect(predPos.dy, closeTo(basePos.dy, 1.0));
    });

    test('moving right — predicted cursor leads filtered cursor in x', () {
      final rBase = _confirmed();
      final rPred = HandGestureRecognizer(
        predictionHorizon: const Duration(milliseconds: 50),
      );
      _run(rPred, [_open(), _open(), _open()]);

      final basePos = driveMoving(rBase, frames: 20);
      final predPos = driveMoving(rPred, frames: 20);

      // Positive x-velocity (moving right on screen) → predicted dx is larger.
      expect(predPos.dx, greaterThan(basePos.dx));
    });

    test('prediction clamps — cursor stays within canvas bounds at extreme velocity',
        () {
      final r = HandGestureRecognizer(
        predictionHorizon: const Duration(milliseconds: 200),
      );
      _run(r, [_open(), _open(), _open()]);

      // Drive hard toward the right edge (indexX → 0.0 → mirrored x → 1.0).
      for (var i = 0; i < 40; i++) {
        final x = (0.5 - i * 0.015).clamp(0.0, 1.0);
        r.process(
          landmarks: _open(indexX: x),
          dt: _dt,
          canvasSize: _size,
        );
      }
      final result = r.process(
        landmarks: _open(indexX: 0.0),
        dt: _dt,
        canvasSize: _size,
      );
      for (final event in result.events.whereType<CanvasHoverEvent>()) {
        expect(event.position.dx, inInclusiveRange(0.0, _size.width));
        expect(event.position.dy, inInclusiveRange(0.0, _size.height));
      }
    });
  });

  group('rotation gesture', () {
    // Drive three frames of two-hand data through a confirmed recognizer and
    // return the CanvasScaleEvent from the third frame (the first emitting frame).
    CanvasScaleEvent driveRotation(
      HandGestureRecognizer r, {
      required double w1x1, required double w1y1,  // frame 2 (baseline) hand1
      required double w2x1, required double w2y1,  // frame 2 (baseline) hand2
      required double w1x2, required double w1y2,  // frame 3 (event)    hand1
      required double w2x2, required double w2y2,  // frame 3 (event)    hand2
    }) {
      // Frame 1: two-hand transition (any position, no event emitted yet).
      r.process(
        landmarks: _handAt(w1x1, w1y1),
        secondHandLandmarks: _handAt(w2x1, w2y1),
        dt: _dt,
        canvasSize: _size,
      );
      // Frame 2: baseline — angle recorded as _prevAngle.
      r.process(
        landmarks: _handAt(w1x1, w1y1),
        secondHandLandmarks: _handAt(w2x1, w2y1),
        dt: _dt,
        canvasSize: _size,
      );
      // Frame 3: emit rotation delta.
      final result = r.process(
        landmarks: _handAt(w1x2, w1y2),
        secondHandLandmarks: _handAt(w2x2, w2y2),
        dt: _dt,
        canvasSize: _size,
      );
      return result.events.whereType<CanvasScaleEvent>().first;
    }

    test('rotation delta is zero when wrists stay horizontal', () {
      final r = _confirmed();
      final scale = driveRotation(
        r,
        w1x1: 0.7, w1y1: 0.5, w2x1: 0.3, w2y1: 0.5,
        w1x2: 0.7, w1y2: 0.5, w2x2: 0.3, w2y2: 0.5,
      );
      expect(scale.rotation, closeTo(0.0, 1e-9));
    });

    test('clockwise rotation yields positive delta', () {
      final r = _confirmed();
      // Baseline: vector (hand1→hand2) points right (angle = 0).
      // Frame 3: hand1 drops (y↑), hand2 rises (y↓) → clockwise on screen.
      final scale = driveRotation(
        r,
        w1x1: 0.7, w1y1: 0.5, w2x1: 0.3, w2y1: 0.5,
        w1x2: 0.7, w1y2: 0.56, w2x2: 0.3, w2y2: 0.44,
      );
      expect(scale.rotation, greaterThan(0.0));
    });

    test('rotation wraps correctly across ±π boundary', () {
      final r = _confirmed();
      // Baseline: vector points slightly above-left → angle ≈ −π + ε.
      // Frame 3:  vector points slightly below-left → angle ≈ +π − ε.
      // Raw delta ≈ +2π; wrapped → small negative (tiny CCW nudge, not ±2π).
      final scale = driveRotation(
        r,
        w1x1: 0.2, w1y1: 0.495, w2x1: 0.8, w2y1: 0.505,
        w1x2: 0.2, w1y2: 0.505, w2x2: 0.8, w2y2: 0.495,
      );
      expect(scale.rotation, lessThan(0.0));
      expect(scale.rotation.abs(), lessThan(math.pi));
    });
  });

  group('filter params', () {
    // Extract the hover position from the last CanvasHoverEvent in a frame list.
    Offset? lastHoverPos(List<PointerInputEvent> events) =>
        events.whereType<CanvasHoverEvent>().lastOrNull?.position;

    test('higher beta reduces lag on fast cursor movement', () {
      // beta=0: speed coefficient off — filter is slow to adapt.
      // beta=0.3: speed-adaptive — much faster response during fast motion.
      final slow = HandGestureRecognizer(beta: 0.0);
      final fast = HandGestureRecognizer(beta: 0.3);

      // Confirm both and warm up at left side (indexX=0.1 → screen x ≈ 720).
      for (final r in [slow, fast]) {
        _run(r, [_open(), _open(), _open()]);                // acquire
        _run(r, List.filled(30, _open(indexX: 0.1)));       // converge
      }

      // Sudden move to right (indexX=0.9 → screen x ≈ 80). Run 5 frames.
      final slowEvents = _run(slow, List.filled(5, _open(indexX: 0.9)));
      final fastEvents = _run(fast, List.filled(5, _open(indexX: 0.9)));

      const target = 80.0;  // (1 − 0.9) × 800
      final slowX = lastHoverPos(slowEvents)?.dx ?? double.infinity;
      final fastX = lastHoverPos(fastEvents)?.dx ?? double.infinity;

      // Higher-beta filter should be closer to the target after 5 frames.
      expect(
        (fastX - target).abs(),
        lessThan((slowX - target).abs()),
        reason: 'fast (β=0.3) should converge faster than slow (β=0.0)',
      );
    });

    test('setFilterParams takes effect on subsequent frames', () {
      final r = HandGestureRecognizer(beta: 0.0);
      _run(r, [_open(), _open(), _open()]);   // acquire
      _run(r, List.filled(30, _open(indexX: 0.1)));  // converge left

      // Switch to high beta and move right.
      r.setFilterParams(minCutoff: 1.0, beta: 0.5);
      final events = _run(r, List.filled(5, _open(indexX: 0.9)));

      // After setFilterParams the recognizer still emits events (not crashed).
      expect(events.whereType<CanvasHoverEvent>(), isNotEmpty);
      // Filter has reset — first frame starts fresh and converges quickly.
      final pos = lastHoverPos(events);
      expect(pos, isNotNull);
      expect((pos!.dx - 80.0).abs(), lessThan(200.0));
    });

    test('setFilterParams getters reflect updated values', () {
      final r = HandGestureRecognizer();
      expect(r.minCutoff, 1.0);
      expect(r.beta, 0.05);
      expect(r.predictionHorizonS, 0.0);

      r.setFilterParams(
        minCutoff: 2.5,
        beta: 0.2,
        predictionHorizon: const Duration(milliseconds: 40),
      );

      expect(r.minCutoff, 2.5);
      expect(r.beta, 0.2);
      expect(r.predictionHorizonS, closeTo(0.04, 1e-9));
    });
  });
}
