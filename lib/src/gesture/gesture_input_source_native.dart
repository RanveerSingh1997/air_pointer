import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/gesture/calibration_result.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_gesture_recognizer.dart';
import 'package:air_pointer/src/gesture/landmark_provider.dart';
import 'package:flutter/widgets.dart';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({
    this.onError,
    this.landmarkProvider,
    Duration dwellDuration = Duration.zero,
    double dwellRadius = 12.0,
  }) {
    _recognizer = HandGestureRecognizer(
      dwellDuration: dwellDuration,
      dwellRadius: dwellRadius,
    );
  }

  final void Function(Object, StackTrace)? onError;

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

  Stream<GestureDebugInfo> get debugInfo => _debugController.stream;

  late final HandGestureRecognizer _recognizer;

  Size _canvasSize = Size.zero;
  StreamSubscription<HandDetectionFrame>? _frameSub;
  DateTime? _prevFrameTime;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  void updateCanvasSize(Size size) => _canvasSize = size;

  void applyCalibration(CalibrationResult result) =>
      _recognizer.setThresholds(result);

  Future<void> initialize() async {
    final provider = landmarkProvider;
    if (provider == null) return;

    _frameSub = provider.frames.listen(
      _onFrame,
      onError: (Object e, StackTrace st) => onError?.call(e, st),
    );
  }

  void _onFrame(HandDetectionFrame frame) {
    final now = DateTime.now();
    final dt = _prevFrameTime != null
        ? now.difference(_prevFrameTime!).inMicroseconds / 1e6
        : 1.0 / 30.0;
    _prevFrameTime = now;

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
    _frameSub?.cancel();
    _frameSub = null;
    landmarkProvider?.dispose();
    unawaited(_debugController.close());
    unawaited(_controller.close());
  }
}
