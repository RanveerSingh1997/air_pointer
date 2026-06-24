import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/gesture/calibration_result.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_gesture_recognizer.dart';
import 'package:air_pointer/src/gesture/hand_tracking_status.dart';
import 'package:air_pointer/src/gesture/landmark_provider.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter/widgets.dart';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({
    this.onError,
    this.landmarkProvider,
    double pinchCloseThreshold = 0.05,
    double pinchOpenThreshold = 0.08,
    int pinchConfirmFrames = 1,
    int acquireFrames = 3,
    int graceFrames = 5,
    double deadzonePx = 3.0,
    double minCutoff = 1.0,
    double beta = 0.05,
    Duration dwellDuration = Duration.zero,
    double dwellRadius = 12.0,
    bool scrollEnabled = false,
    double scrollScale = 3.0,
    Duration predictionHorizon = Duration.zero,
    double swipeThreshold = 0.0,
    Duration longPressDuration = Duration.zero,
    Duration doubleTapWindow = const Duration(milliseconds: 300),
    this.maxHands = 2,
  }) {
    _recognizer = HandGestureRecognizer(
      pinchCloseThreshold: pinchCloseThreshold,
      pinchOpenThreshold: pinchOpenThreshold,
      pinchConfirmFrames: pinchConfirmFrames,
      acquireFrames: acquireFrames,
      graceFrames: graceFrames,
      deadzonePx: deadzonePx,
      minCutoff: minCutoff,
      beta: beta,
      dwellDuration: dwellDuration,
      dwellRadius: dwellRadius,
      scrollEnabled: scrollEnabled,
      scrollScale: scrollScale,
      predictionHorizon: predictionHorizon,
      swipeThreshold: swipeThreshold,
      longPressDuration: longPressDuration,
      doubleTapWindow: doubleTapWindow,
    );
  }

  final void Function(Object, StackTrace)? onError;

  /// Maximum number of hands the backend should detect simultaneously.
  ///
  /// Stored so callers can query the configured value and pass it to their
  /// [LandmarkProvider] implementation (e.g. to configure a native ML model).
  final int maxHands;

  /// Optional native hand-detection backend.
  ///
  /// When non-null, frames from this provider are piped through the gesture
  /// recognizer and emitted as [PointerInputEvent]s. When null, all streams
  /// remain empty — useful during development before a provider is wired up.
  ///
  /// [GestureInputSource] takes ownership and calls [LandmarkProvider.dispose]
  /// during [dispose].
  final LandmarkProvider? landmarkProvider;

  final StreamController<PointerInputEvent> _controller =
      StreamController.broadcast();
  final StreamController<GestureDebugInfo> _debugController =
      StreamController.broadcast();
  final StreamController<HandTrackingStatus> _statusController =
      StreamController.broadcast();

  Stream<GestureDebugInfo> get debugInfo => _debugController.stream;

  /// Lifecycle stream: initializing → cameraReady → tracking ⇄ lost → error.
  ///
  /// Only emits when a [LandmarkProvider] is configured. Empty otherwise.
  Stream<HandTrackingStatus> get statusStream => _statusController.stream;

  late final HandGestureRecognizer _recognizer;

  Size _canvasSize = Size.zero;
  StreamSubscription<HandDetectionFrame>? _frameSub;
  DateTime? _prevFrameTime;
  bool _wasTracking = false;
  bool _hasErrored = false;
  bool _cameraReadyEmitted = false;
  RecognizedGesture _lastGesture = RecognizedGesture.none;
  RecognizedGesture _lastSecondGesture = RecognizedGesture.none;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  void updateCanvasSize(Size size) => _canvasSize = size;

  void applyCalibration(CalibrationResult result) =>
      _recognizer.setThresholds(result);

  /// Updates the cursor-position smoothing filter.
  ///
  /// Safe to call at any time; the filter resets to the new parameters
  /// immediately. See [HandGestureRecognizer.setFilterParams] for details.
  void setFilterParams({
    required double minCutoff,
    required double beta,
    Duration predictionHorizon = Duration.zero,
  }) => _recognizer.setFilterParams(
        minCutoff: minCutoff,
        beta: beta,
        predictionHorizon: predictionHorizon,
      );

  Future<void> initialize() async {
    final provider = landmarkProvider;
    if (provider == null || _frameSub != null) return;

    _emitStatus(const HandTrackingInitializing());
    _frameSub = provider.frames.listen(
      _onFrame,
      onError: (Object e, StackTrace st) {
        if (!_hasErrored) {
          _hasErrored = true;
          _emitStatus(HandTrackingError(e));
        }
        onError?.call(e, st);
      },
    );
  }

  void _emitStatus(HandTrackingStatus status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _onFrame(HandDetectionFrame frame) {
    final now = DateTime.now();
    final dt = _prevFrameTime != null
        ? now.difference(_prevFrameTime!).inMicroseconds / 1e6
        : 1.0 / 30.0;
    _prevFrameTime = now;

    if (!_cameraReadyEmitted) {
      _cameraReadyEmitted = true;
      _emitStatus(const HandTrackingCameraReady());
    }

    final lms = frame.landmarks.isEmpty ? null : frame.landmarks;
    final secondLms =
        frame.secondHandLandmarks.isEmpty ? null : frame.secondHandLandmarks;

    final result = _recognizer.process(
      landmarks: lms,
      secondHandLandmarks: secondLms,
      dt: dt,
      canvasSize: _canvasSize,
    );

    for (final e in result.events) {
      if (!_controller.isClosed) _controller.add(e);
    }

    // Emit CanvasGestureEvent on leading edge of each new discrete gesture.
    final gesture = frame.detectedGesture;
    if (gesture != RecognizedGesture.none && gesture != _lastGesture) {
      if (!_controller.isClosed) {
        _controller.add(CanvasGestureEvent(gesture: gesture));
      }
    }
    _lastGesture = gesture;

    final secondGesture = frame.secondHandGesture;
    if (secondGesture != RecognizedGesture.none &&
        secondGesture != _lastSecondGesture) {
      if (!_controller.isClosed) {
        _controller.add(
          CanvasGestureEvent(gesture: secondGesture, isSecondHand: true),
        );
      }
    }
    _lastSecondGesture = secondGesture;

    if (!_hasErrored) {
      final nowTracking = result.debug.phase == GesturePhase.hovering ||
          result.debug.phase == GesturePhase.down;
      if (!_wasTracking && nowTracking) {
        _emitStatus(const HandTrackingTracking());
      } else if (_wasTracking && !nowTracking) {
        _emitStatus(const HandTrackingLost());
        _lastGesture = RecognizedGesture.none;
        _lastSecondGesture = RecognizedGesture.none;
      }
      _wasTracking = nowTracking;
    }

    if (!_debugController.isClosed) {
      _debugController.add(GestureDebugInfo(
        phase: result.debug.phase,
        pinchDistance: result.debug.pinchDistance,
        landmarks: result.debug.landmarks,
        secondHandLandmarks: result.debug.secondHandLandmarks,
        isTwoHandActive: result.debug.isTwoHandActive,
        handedness: frame.handedness,
        secondHandedness: frame.secondHandedness,
        detectedGesture: frame.detectedGesture,
        secondHandGesture: frame.secondHandGesture,
        dwellProgress: result.debug.dwellProgress,
        isPointing: result.debug.isPointing,
      ));
    }
  }

  @override
  Widget buildSurface({required Widget child}) => child;

  Widget buildCameraPreview({double? width, double? height}) =>
      landmarkProvider?.buildPreview(width: width, height: height) ??
      const SizedBox.shrink();

  @override
  void dispose() {
    _recognizer.reset();
    unawaited(_frameSub?.cancel());
    _frameSub = null;
    landmarkProvider?.dispose();
    unawaited(_statusController.close());
    unawaited(_debugController.close());
    unawaited(_controller.close());
  }
}
