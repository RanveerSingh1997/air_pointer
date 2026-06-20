import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';

/// Lifecycle state of the gesture recogniser's hand-tracking session.
enum GesturePhase {
  /// Hand appeared in frame; waiting for N consecutive frames to confirm.
  acquiring,

  /// Hand confirmed and tracked, no pinch active.
  hovering,

  /// Pinch gesture active — drag in progress.
  down,

  /// Hand disappeared; within the grace window before declaring it lost.
  grace,

  /// No hand detected and the grace window has expired.
  lost,
}

/// Which hand MediaPipe classified, from the camera's perspective.
///
/// In a mirrored front-camera view, a reported [left] hand appears on the
/// user's right side. Consumers that display handedness to users should flip
/// the label accordingly.
enum Handedness { left, right, unknown }

/// Snapshot of [HandGestureRecognizer] state emitted each frame by
/// [GestureInputSource.debugInfo]. Useful for building debug overlays.
final class GestureDebugInfo {
  const GestureDebugInfo({
    required this.phase,
    required this.pinchDistance,
    required this.landmarks,
    this.secondHandLandmarks = const [],
    this.isTwoHandActive = false,
    this.handedness = Handedness.unknown,
    this.secondHandedness = Handedness.unknown,
    this.detectedGesture = RecognizedGesture.none,
    this.secondHandGesture = RecognizedGesture.none,
    this.dwellProgress = 0.0,
    this.isPointing = false,
    this.workerLatencyMs = 0,
    this.roundTripMs = 0,
  });

  final GesturePhase phase;

  /// Raw Euclidean distance between thumb tip and index tip (normalised 0–1).
  final double pinchDistance;

  /// The 21 MediaPipe landmarks for the primary hand, normalised to [0, 1].
  /// Empty when no hand is detected.
  final List<HandLandmarkPoint> landmarks;

  /// The 21 MediaPipe landmarks for the second hand when in two-hand mode,
  /// normalised to [0, 1]. Empty when fewer than two hands are detected.
  final List<HandLandmarkPoint> secondHandLandmarks;

  /// True while a two-hand spread/pinch gesture is active.
  final bool isTwoHandActive;

  /// Handedness of the primary hand as reported by MediaPipe.
  /// [Handedness.unknown] when no hand is detected or the model did not
  /// provide a classification.
  final Handedness handedness;

  /// Handedness of the second hand. [Handedness.unknown] when fewer than two
  /// hands are detected.
  final Handedness secondHandedness;

  /// Discrete gesture classified for the primary hand by the ML backend.
  ///
  /// Always [RecognizedGesture.none] on web (the MediaPipe HandLandmarker used
  /// there provides landmarks only, not gesture labels). On native, set by the
  /// [LandmarkProvider] — e.g. via `hand_detection`'s gesture classifier.
  final RecognizedGesture detectedGesture;

  /// Discrete gesture classified for the second hand.
  /// [RecognizedGesture.none] when fewer than two hands are detected.
  final RecognizedGesture secondHandGesture;

  /// Dwell-click progress, 0.0–1.0.
  ///
  /// Rises from 0.0 to 1.0 as the cursor holds still in [GesturePhase.hovering].
  /// Resets to 0.0 immediately after a dwell tap fires, when the cursor moves
  /// beyond the deadzone, or when the phase leaves [GesturePhase.hovering].
  /// Always 0.0 when dwell-click is disabled.
  final double dwellProgress;

  /// True while the pointing-finger scroll gesture is active (index extended,
  /// middle curled). False when scroll is disabled or the gesture is absent.
  final bool isPointing;

  /// Time the web worker spent on inference for this frame (ms), 0 on native.
  final double workerLatencyMs;

  /// Wall-clock round-trip time from sending the frame to receiving results (ms).
  final int roundTripMs;
}
