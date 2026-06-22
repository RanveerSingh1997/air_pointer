import 'dart:math' as math;

import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/filter/one_euro_filter.dart';
import 'package:air_pointer/src/gesture/calibration_result.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/hand_landmark_type.dart';
import 'package:flutter/painting.dart';

/// Pure-Dart gesture state machine for MediaPipe hand landmarks.
///
/// Accepts one frame of landmarks at a time via [process] and returns the
/// [PointerInputEvent]s to emit plus a [GestureDebugInfo] snapshot. The
/// caller is responsible for driving the frame loop and converting raw
/// JS-interop data into [HandLandmarkPoint] before passing it here.
///
/// Key behaviours:
/// - **Acquisition gate**: requires [acquireFrames] consecutive frames with
///   landmarks before the hand is considered present.
/// - **Clutch (Midas-touch guard)**: after hand confirmation, a pinch is only
///   accepted after the hand has first been observed open. This prevents an
///   accidental drag when the hand enters the frame already pinched.
/// - **Hysteresis**: pinch closes at [pinchCloseThreshold] and opens at
///   [pinchOpenThreshold] to prevent chatter near the threshold.
/// - **Pinch confirm gate**: requires [pinchConfirmFrames] consecutive frames
///   below [pinchCloseThreshold] before `CanvasDownEvent` is emitted.
///   Default 1 (immediate). Raise to 2 to eliminate single-frame noise spikes.
/// - **Grace window**: [graceFrames] frames without a hand before the session
///   is declared lost; the cursor freezes during grace rather than jumping.
/// - **Cancel on exit**: emits [CanvasCancelEvent] (not [CanvasUpEvent]) when
///   the hand exits during an active drag so consumers can discard the action.
/// - **Two-hand spread**: when a second hand is detected, single-hand drag is
///   cancelled and [CanvasScaleEvent]s are emitted from the spread/pinch
///   gesture. [CanvasScaleEndEvent] fires when the second hand leaves.
/// - **Filter reset**: [OneEuroFilter] state is cleared on session loss, not
///   on grace entry, so a hand returning within the grace window resumes
///   smoothly.
final class HandGestureRecognizer {
  HandGestureRecognizer({
    double pinchCloseThreshold = 0.05,
    double pinchOpenThreshold = 0.08,
    this.acquireFrames = 3,
    this.graceFrames = 5,
    this.deadzonePx = 3.0,
    this.pinchConfirmFrames = 1,
    double minCutoff = 1.0,
    double beta = 0.05,
    Duration dwellDuration = Duration.zero,
    this.dwellRadius = 12.0,
    bool scrollEnabled = false,
    this.scrollScale = 3.0,
    Duration predictionHorizon = Duration.zero,
    this.swipeThreshold = 0.0,
    Duration longPressDuration = Duration.zero,
    Duration doubleTapWindow = const Duration(milliseconds: 300),
  })  : _pinchCloseThreshold = pinchCloseThreshold,
        _pinchOpenThreshold = pinchOpenThreshold,
        _dwellThresholdS = dwellDuration.inMicroseconds / 1e6,
        _longPressDurationS = longPressDuration.inMicroseconds / 1e6,
        _doubleTapWindowS = doubleTapWindow.inMicroseconds / 1e6,
        _predictionHorizonS = predictionHorizon.inMicroseconds / 1e6,
        _scrollEnabled = scrollEnabled,
        _minCutoff = minCutoff,
        _beta = beta,
        _xFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta),
        _yFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta);

  /// Normalised pinch distance (thumb–index) that closes the pinch.
  double get pinchCloseThreshold => _pinchCloseThreshold;

  /// Normalised pinch distance (thumb–index) that opens the pinch.
  double get pinchOpenThreshold => _pinchOpenThreshold;

  /// Current minimum cutoff frequency of the position filter (Hz).
  double get minCutoff => _minCutoff;

  /// Current speed coefficient of the position filter.
  double get beta => _beta;

  /// Current prediction horizon in seconds (0 = no prediction).
  double get predictionHorizonS => _predictionHorizonS;

  /// Long-press duration in seconds (0 = disabled).
  double get longPressDurationS => _longPressDurationS;

  /// Double-tap detection window in seconds.
  double get doubleTapWindowS => _doubleTapWindowS;

  double _pinchCloseThreshold;
  double _pinchOpenThreshold;

  /// Consecutive frames required to confirm a newly detected hand.
  final int acquireFrames;

  /// Frames without a hand before the tracking session is declared lost.
  final int graceFrames;

  /// Minimum move distance in screen pixels before a drag event is emitted.
  final double deadzonePx;

  /// Consecutive frames below [pinchCloseThreshold] required before a drag
  /// begins. Default 1 (immediate). Set to 2 to suppress single-frame noise
  /// spikes near the threshold without adding perceptible latency at 30fps.
  final int pinchConfirmFrames;

  int _pinchConfirmCount = 0;

  /// Cursor must stay within this radius (screen pixels) for the dwell timer
  /// to accumulate. Moving beyond it resets the timer to zero.
  final double dwellRadius;

  /// Multiplier applied to the raw screen-pixel delta when emitting
  /// [CanvasScrollEvent] during a pointing-finger scroll gesture.
  final double scrollScale;

  /// Minimum cursor speed in screen pixels/s required to emit a
  /// [CanvasSwipeEvent]. Set to 0 (the default) to disable swipe detection.
  final double swipeThreshold;

  // Swipe detection state.
  double _swipeCooldownS = 0.0;

  OneEuroFilter _xFilter;
  OneEuroFilter _yFilter;
  double _minCutoff;
  double _beta;

  // Dwell-click / long-press / double-tap state.
  final double _dwellThresholdS;      // 0 = dwell-tap disabled
  final double _longPressDurationS;   // 0 = long-press disabled
  final double _doubleTapWindowS;
  double _predictionHorizonS;  // 0 = prediction disabled
  Offset _dwellAnchor = Offset.zero;
  double _dwellElapsedS = 0;
  bool _mustMoveBeforeDwell = false;
  double _timeSinceLastDwellS = double.infinity;

  // Pointing-finger scroll state.
  final bool _scrollEnabled;
  Offset? _prevScrollPosition;  // null = first pointing frame or not pointing
  bool _isScrollActive = false; // true only after first pointing frame (baseline captured)

  GesturePhase _phase = GesturePhase.lost;
  int _acquireCount = 0;
  int _graceCount = 0;
  Offset _lastPosition = Offset.zero;
  double _lastPinchDistance = 1.0;

  // Clutch: true until the newly-confirmed hand is observed open for the
  // first time. Prevents an immediate drag when the hand enters pinched.
  bool _mustOpenFirst = false;

  // Two-hand state.
  bool _twoHandActive = false;
  double _prevSpread = 0;
  Offset _prevCentroidScreen = Offset.zero;
  double _prevAngle = 0.0;

  GesturePhase get phase => _phase;

  /// Process one frame. Pass [landmarks] = null (or a list shorter than 21)
  /// when no hand is detected this frame. [secondHandLandmarks] may be
  /// supplied when the tracker returns two hands.
  ({List<PointerInputEvent> events, GestureDebugInfo debug}) process({
    required List<HandLandmarkPoint>? landmarks,
    required double dt,
    required Size canvasSize,
    List<HandLandmarkPoint>? secondHandLandmarks,
  }) {
    final firstOk = landmarks != null && landmarks.length >= 21;
    final secondOk =
        secondHandLandmarks != null && secondHandLandmarks.length >= 21;

    final List<PointerInputEvent> events;

    if (firstOk && secondOk) {
      events = _handleTwoHand(landmarks, secondHandLandmarks, dt, canvasSize);
    } else {
      // Single-hand or no-hand path. Exit two-hand mode if active.
      final exitEvents = _twoHandActive
          ? <PointerInputEvent>[const CanvasScaleEndEvent()]
          : const <PointerInputEvent>[];
      if (_twoHandActive) {
        _twoHandActive = false;
        _prevSpread = 0;
        // Require open hand after two-hand gesture, same as after acquisition.
        _mustOpenFirst = true;
      }
      final singleEvents =
          firstOk ? _handleHand(landmarks, dt, canvasSize) : _handleNoHand();
      events = [...exitEvents, ...singleEvents];
    }

    return (
      events: events,
      debug: GestureDebugInfo(
        phase: _phase,
        pinchDistance: _lastPinchDistance,
        landmarks: firstOk ? landmarks : const [],
        secondHandLandmarks: secondOk ? secondHandLandmarks : const [],
        isTwoHandActive: _twoHandActive,
        dwellProgress: _dwellProgress,
        isPointing: _scrollEnabled && _isScrollActive,
      ),
    );
  }

  /// Replaces the position-smoothing filter with new parameters.
  ///
  /// Safe to call at any time; the new filter starts fresh (state is not
  /// carried over from the old one). The cursor may jump slightly on the next
  /// frame while the filter settles — for best results call this between
  /// tracking sessions rather than mid-drag.
  ///
  /// - [minCutoff]: base cutoff frequency in Hz (lower = smoother, more lag;
  ///   higher = more responsive, more jitter when still). Default 1.0.
  /// - [beta]: speed coefficient (higher = less lag during fast motion at the
  ///   cost of slightly more jitter). Default 0.05.
  /// - [predictionHorizon]: how far ahead to project position based on the
  ///   filter's velocity estimate, to compensate for lag. Default zero.
  void setFilterParams({
    required double minCutoff,
    required double beta,
    Duration predictionHorizon = Duration.zero,
  }) {
    _minCutoff = minCutoff;
    _beta = beta;
    _predictionHorizonS = predictionHorizon.inMicroseconds / 1e6;
    _xFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta);
    _yFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta);
  }

  /// Updates the pinch detection thresholds without resetting tracking state.
  ///
  /// Call this after [GestureCalibrator.compute] to apply user-specific values.
  /// Avoid calling mid-drag; the calibration flow naturally prevents this since
  /// it runs before the user re-enters the canvas.
  void setThresholds(CalibrationResult result) {
    assert(
      result.pinchOpenThreshold > result.pinchCloseThreshold,
      'CalibrationResult invariant violated',
    );
    _pinchCloseThreshold = result.pinchCloseThreshold;
    _pinchOpenThreshold = result.pinchOpenThreshold;
  }

  /// Resets all state — equivalent to constructing a fresh instance.
  void reset() {
    _phase = GesturePhase.lost;
    _acquireCount = 0;
    _graceCount = 0;
    _lastPosition = Offset.zero;
    _lastPinchDistance = 1.0;
    _mustOpenFirst = false;
    _pinchConfirmCount = 0;
    _twoHandActive = false;
    _prevSpread = 0;
    _prevCentroidScreen = Offset.zero;
    _prevAngle = 0.0;
    _dwellAnchor = Offset.zero;
    _dwellElapsedS = 0;
    _mustMoveBeforeDwell = false;
    _timeSinceLastDwellS = double.infinity;
    _prevScrollPosition = null;
    _isScrollActive = false;
    _swipeCooldownS = 0.0;
    _xFilter.reset();
    _yFilter.reset();
  }

  List<PointerInputEvent> _handleNoHand() {
    _prevScrollPosition = null;
    _isScrollActive = false;
    _pinchConfirmCount = 0;

    switch (_phase) {
      case GesturePhase.lost:
        return const [];

      case GesturePhase.acquiring:
        _acquireCount = 0;
        _phase = GesturePhase.lost;
        _xFilter.reset();
        _yFilter.reset();
        _dwellElapsedS = 0;
        _mustMoveBeforeDwell = false;
        return const [];

      case GesturePhase.hovering:
        _graceCount = 1;
        _phase = GesturePhase.grace;
        // Dwell progress is preserved through brief occlusions: if the hand
        // returns within the grace window at the same position, the timer
        // continues from where it left off. _checkDwell resets it if the
        // cursor lands outside dwellRadius of the anchor on re-entry.
        return const [];

      case GesturePhase.down:
        // Cancel the active drag immediately; freeze in grace until confirmed lost.
        _graceCount = 1;
        _phase = GesturePhase.grace;
        _dwellElapsedS = 0;
        _mustMoveBeforeDwell = false;
        return [const CanvasCancelEvent()];

      case GesturePhase.grace:
        _graceCount++;
        if (_graceCount >= graceFrames) {
          _phase = GesturePhase.lost;
          // Reset filters and dwell here (not on grace entry) so a within-grace
          // return resumes smoothly from the last valid filter/dwell state.
          _xFilter.reset();
          _yFilter.reset();
          _dwellElapsedS = 0;
          _mustMoveBeforeDwell = false;
        }
        return const [];
    }
  }

  List<PointerInputEvent> _handleHand(
    List<HandLandmarkPoint> landmarks,
    double dt,
    Size canvasSize,
  ) {
    // Advance the acquisition counter or recover from grace.
    if (_phase == GesturePhase.lost || _phase == GesturePhase.acquiring) {
      _acquireCount++;
      if (_acquireCount < acquireFrames) {
        _phase = GesturePhase.acquiring;
        return const [];
      }
      // Confirmed — begin a fresh session; require explicit open before pinch.
      _acquireCount = 0;
      _phase = GesturePhase.hovering;
      _mustOpenFirst = true;
    } else if (_phase == GesturePhase.grace) {
      _graceCount = 0;
      _phase = GesturePhase.hovering;  // recovered within grace window
    }

    // _phase is now guaranteed to be hovering or down.
    final thumb = landmarks.getLandmark(HandLandmarkType.thumbTip);
    final index = landmarks.getLandmark(HandLandmarkType.indexTip);
    final dx = thumb.x - index.x;
    final dy = thumb.y - index.y;
    _lastPinchDistance = math.sqrt(dx * dx + dy * dy);

    // Clear the Midas-touch guard as soon as the hand is clearly open.
    // Must happen before the pinch-close check so the guard lifts on the same
    // frame the hand opens (e.g. open hand immediately after confirmation).
    if (_mustOpenFirst && _lastPinchDistance > _pinchOpenThreshold) {
      _mustOpenFirst = false;
    }

    // Smooth the index-fingertip, mirroring x for a natural front-camera view.
    final smoothX = _xFilter.filter(1.0 - index.x, dt);
    final smoothY = _yFilter.filter(index.y, dt);

    // Velocity prediction: project the smoothed position forward by
    // _predictionHorizonS to compensate for the lag the filter introduces.
    // Clamp to [0,1] so the cursor cannot be predicted off-screen.
    final predX = _predictionHorizonS > 0
        ? (smoothX + _xFilter.velocity * _predictionHorizonS).clamp(0.0, 1.0)
        : smoothX;
    final predY = _predictionHorizonS > 0
        ? (smoothY + _yFilter.velocity * _predictionHorizonS).clamp(0.0, 1.0)
        : smoothY;

    final position = Offset(
      predX * canvasSize.width,
      predY * canvasSize.height,
    );

    // Hovering: pinch checked first (beats scroll), then pointing scroll, then dwell.
    if (_phase == GesturePhase.hovering) {
      // Pinch-close takes priority — drag must work even when middle finger is curled.
      if (!_mustOpenFirst && _lastPinchDistance < _pinchCloseThreshold) {
        _pinchConfirmCount++;
        if (_pinchConfirmCount >= pinchConfirmFrames) {
          _pinchConfirmCount = 0;
          _phase = GesturePhase.down;
          _lastPosition = position;
          _dwellElapsedS = 0;
          _mustMoveBeforeDwell = false;
          _prevScrollPosition = null;
          _isScrollActive = false;
          return [CanvasDownEvent(position: position)];
        }
        // Still within the confirm window — hover in place.
        return [CanvasHoverEvent(position: position)];
      }
      _pinchConfirmCount = 0;
      if (_scrollEnabled && _detectPointing(landmarks)) {
        // Suppress dwell accumulation; do NOT clear _mustMoveBeforeDwell so
        // the post-dwell guard persists across a scroll session.
        _dwellAnchor = position;
        _dwellElapsedS = 0;
        final prev = _prevScrollPosition;
        _prevScrollPosition = position;
        if (prev == null) {
          // First pointing frame: record baseline, no delta yet.
          return [CanvasHoverEvent(position: position)];
        }
        _isScrollActive = true;
        final scrollDy = (position.dy - prev.dy) * scrollScale;
        final scrollDx = (position.dx - prev.dx) * scrollScale;
        return [CanvasScrollEvent(position: position, delta: Offset(scrollDx, scrollDy))];
      }
      _prevScrollPosition = null;
      _isScrollActive = false;
      final dwellEvents = _checkDwellEvents(position, dt);
      if (dwellEvents.isNotEmpty) return dwellEvents;
    } else {
      // In down phase: keep anchor current so release-to-hover starts fresh.
      _dwellAnchor = position;
      _dwellElapsedS = 0;
      _mustMoveBeforeDwell = false;
      _prevScrollPosition = null;
      _isScrollActive = false;
      _pinchConfirmCount = 0;
    }

    // Hysteresis: pinch-close was handled inside the hovering block above.
    if (_phase == GesturePhase.down &&
        _lastPinchDistance > _pinchOpenThreshold) {
      _phase = GesturePhase.hovering;
      // Reset anchor so dwell restarts from the release position.
      _dwellAnchor = position;
      _dwellElapsedS = 0;
      _mustMoveBeforeDwell = false;
      return [CanvasUpEvent(position: _lastPosition)];
    }
    if (_phase == GesturePhase.down) {
      final delta = position - _lastPosition;
      if (delta.distance >= deadzonePx) {
        _lastPosition = position;
        return [CanvasMoveEvent(position: position)];
      }
      return const [];
    }
    final swipe = _checkSwipe(canvasSize, dt);
    if (swipe != null) return [swipe, CanvasHoverEvent(position: position)];
    return [CanvasHoverEvent(position: position)];
  }

  // Detects a fast directional movement and returns a [CanvasSwipeEvent] when
  // cursor velocity exceeds [swipeThreshold] in a cardinal direction.
  //
  // Uses the OneEuroFilter's already-computed velocity to avoid extra state.
  // A 400 ms cooldown prevents multiple swipes from one gesture.
  CanvasSwipeEvent? _checkSwipe(Size canvasSize, double dt) {
    if (swipeThreshold <= 0) return null;
    _swipeCooldownS = math.max(0, _swipeCooldownS - dt);
    if (_swipeCooldownS > 0) return null;

    // Filter velocity is in normalised-coord/s; convert to screen px/s.
    // x is already mirrored in the filter input so positive = cursor moves right.
    final velX = _xFilter.velocity * canvasSize.width;
    final velY = _yFilter.velocity * canvasSize.height;
    final speed = math.sqrt(velX * velX + velY * velY);
    if (speed < swipeThreshold) return null;

    final absX = velX.abs();
    final absY = velY.abs();
    // Require 60/40 directional dominance to avoid diagonal false-positives.
    if (absX > absY * 1.5) {
      _swipeCooldownS = 0.4;
      return CanvasSwipeEvent(
        direction: velX > 0 ? SwipeDirection.right : SwipeDirection.left,
        velocity: speed,
      );
    }
    if (absY > absX * 1.5) {
      _swipeCooldownS = 0.4;
      return CanvasSwipeEvent(
        direction: velY > 0 ? SwipeDirection.down : SwipeDirection.up,
        velocity: speed,
      );
    }
    return null;
  }

  List<PointerInputEvent> _handleTwoHand(
    List<HandLandmarkPoint> hand1,
    List<HandLandmarkPoint> hand2,
    double dt,
    Size canvasSize,
  ) {
    final events = <PointerInputEvent>[];

    if (!_twoHandActive) {
      // Transition into two-hand mode: cancel any active drag first.
      if (_phase == GesturePhase.down) {
        events.add(const CanvasCancelEvent());
        _phase = GesturePhase.hovering;
      }
      _twoHandActive = true;
      _prevSpread = 0;  // marks "first frame" — no scale emitted yet
      // Two-hand mode is not hovering; dwell and scroll must restart when returning.
      _dwellElapsedS = 0;
      _mustMoveBeforeDwell = false;
      _prevScrollPosition = null;
      _isScrollActive = false;
    }

    // Use wrist of each hand for stable spread measurement.
    final w1 = hand1.getLandmark(HandLandmarkType.wrist);
    final w2 = hand2.getLandmark(HandLandmarkType.wrist);
    final spreadDx = w1.x - w2.x;
    final spreadDy = w1.y - w2.y;
    final spread = math.sqrt(spreadDx * spreadDx + spreadDy * spreadDy);
    final angle = math.atan2(spreadDy, spreadDx);

    // Centroid of the two wrists, mirrored for front-camera display.
    // Note: pan delta from centroid drift is expected during spread/pinch
    // gestures and is consistent with how MouseInputSource handles two-finger
    // trackpad gestures.
    final cx = (w1.x + w2.x) / 2;
    final cy = (w1.y + w2.y) / 2;
    final centroidScreen = Offset(
      (1 - cx) * canvasSize.width,
      cy * canvasSize.height,
    );

    if (_prevSpread < 0.001) {
      // First two-hand frame: record baseline, emit no scale change yet.
      _prevSpread = spread;
      _prevCentroidScreen = centroidScreen;
      _prevAngle = angle;
      return events;  // may contain CanvasCancelEvent from mode transition
    }

    final scaleDelta = _prevSpread > 0.001 ? spread / _prevSpread : 1.0;
    final panDelta = centroidScreen - _prevCentroidScreen;

    // Shortest-path angle delta, wrapping through the ±π discontinuity.
    var rotationDelta = angle - _prevAngle;
    if (rotationDelta > math.pi) rotationDelta -= 2 * math.pi;
    if (rotationDelta < -math.pi) rotationDelta += 2 * math.pi;

    _prevSpread = spread;
    _prevCentroidScreen = centroidScreen;
    _prevAngle = angle;

    events.add(CanvasScaleEvent(
      focalPoint: centroidScreen,
      scaleDelta: scaleDelta,
      panDelta: panDelta,
      rotation: rotationDelta,
    ));

    return events;
  }

  // Returns dwell-tap, double-tap, or long-press events when the cursor holds
  // still long enough. Returns an empty list when nothing fires this frame.
  List<PointerInputEvent> _checkDwellEvents(Offset position, double dt) {
    if (_dwellThresholdS <= 0 && _longPressDurationS <= 0) return const [];

    _timeSinceLastDwellS += dt;

    if (_mustMoveBeforeDwell) {
      if ((position - _dwellAnchor).distance >= dwellRadius) {
        _mustMoveBeforeDwell = false;
        _dwellAnchor = position;
        _dwellElapsedS = 0;
      }
      return const [];
    }

    if ((position - _dwellAnchor).distance >= dwellRadius) {
      _dwellAnchor = position;
      _dwellElapsedS = 0;
      return const [];
    }

    _dwellElapsedS += dt;

    // Long-press fires when its threshold is reached (checked before dwell-tap
    // so a shorter longPressDuration always wins over a longer dwellDuration).
    if (_longPressDurationS > 0 && _dwellElapsedS >= _longPressDurationS) {
      _dwellElapsedS = 0;
      _mustMoveBeforeDwell = true;
      return [CanvasLongPressEvent(position: position)];
    }

    if (_dwellThresholdS > 0 && _dwellElapsedS >= _dwellThresholdS) {
      _dwellElapsedS = 0;
      _mustMoveBeforeDwell = true;
      final isDouble = _timeSinceLastDwellS <= _doubleTapWindowS;
      _timeSinceLastDwellS = 0;
      return isDouble
          ? [
              CanvasTapEvent(position: position),
              CanvasDoubleTapEvent(position: position),
            ]
          : [CanvasTapEvent(position: position)];
    }

    return const [];
  }

  double get _dwellProgress {
    if (_mustMoveBeforeDwell) return 0.0;
    // Use whichever active threshold is shorter.
    final t = switch ((_dwellThresholdS > 0, _longPressDurationS > 0)) {
      (true, true) => math.min(_dwellThresholdS, _longPressDurationS),
      (true, false) => _dwellThresholdS,
      (false, true) => _longPressDurationS,
      (false, false) => 0.0,
    };
    if (t <= 0) return 0.0;
    return (_dwellElapsedS / t).clamp(0.0, 1.0);
  }

  // Returns true when the index finger is extended and the middle finger is
  // curled. MediaPipe Y: 0 = top, 1 = bottom; extended tip has lower Y than PIP.
  //
  // The original stricter check also required the pinky to be curled, but that
  // caused false negatives when users naturally extend the pinky while pointing.
  // The middle-curled check is sufficient to exclude the common two-finger
  // (index + middle) open-hand gesture that would otherwise mis-trigger scrolling.
  bool _detectPointing(List<HandLandmarkPoint> landmarks) {
    final indexTip = landmarks.getLandmark(HandLandmarkType.indexTip);
    final indexPip = landmarks.getLandmark(HandLandmarkType.indexPip);
    final middleTip = landmarks.getLandmark(HandLandmarkType.middleTip);
    final middlePip = landmarks.getLandmark(HandLandmarkType.middlePip);
    return indexTip.y < indexPip.y && middleTip.y > middlePip.y;
  }
}
