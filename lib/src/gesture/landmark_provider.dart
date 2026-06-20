import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter/widgets.dart';

/// A single frame of hand-detection data from a native ML inference backend.
final class HandDetectionFrame {
  const HandDetectionFrame({
    this.landmarks = const [],
    this.secondHandLandmarks = const [],
    this.handedness = Handedness.unknown,
    this.secondHandedness = Handedness.unknown,
    this.detectedGesture = RecognizedGesture.none,
    this.secondHandGesture = RecognizedGesture.none,
  });

  /// 21 MediaPipe-convention landmarks for the primary detected hand,
  /// normalised to [0, 1]. Empty when no hand is detected this frame.
  final List<HandLandmarkPoint> landmarks;

  /// Landmarks for a second hand. Empty when fewer than two hands are visible.
  final List<HandLandmarkPoint> secondHandLandmarks;

  /// Handedness of the primary hand as classified by the model.
  final Handedness handedness;

  /// Handedness of the second hand. [Handedness.unknown] when absent.
  final Handedness secondHandedness;

  /// Discrete gesture classified for the primary hand.
  /// [RecognizedGesture.none] when no hand is detected or the backend does
  /// not provide gesture classification.
  final RecognizedGesture detectedGesture;

  /// Discrete gesture classified for the second hand.
  /// [RecognizedGesture.none] when fewer than two hands are present.
  final RecognizedGesture secondHandGesture;
}

/// Contract for a native hand-detection backend.
///
/// Implement this interface using whichever ML library fits your app —
/// `hand_detection`, on-device MediaPipe, etc. — then pass an instance to
/// [GestureInputSource]. `air_pointer` itself carries no native ML dependency.
///
/// ## Camera permissions
/// Your implementation is responsible for requesting camera access before
/// emitting frames. Add the required permission entries to the host app's
/// manifests:
/// - **Android**: `<uses-permission android:name="android.permission.CAMERA"/>`
///   in `AndroidManifest.xml`
/// - **iOS / macOS**: `NSCameraUsageDescription` in `Info.plist`
///
/// ## Minimal implementation with `hand_detection`
/// ```dart
/// import 'package:hand_detection/hand_detection.dart';
/// import 'package:camera/camera.dart';
///
/// class HandDetectionProvider implements LandmarkProvider {
///   HandDetectionProvider({required this.detector, required this.camera});
///
///   final HandDetector detector;
///   final CameraController camera;
///
///   final _ctrl = StreamController<HandDetectionFrame>.broadcast();
///
///   @override
///   Stream<HandDetectionFrame> get frames => _ctrl.stream;
///
///   void processImage(CameraImage image) async {
///     final hand = await detector.detect(image);
///     if (hand == null) { _ctrl.add(const HandDetectionFrame()); return; }
///     _ctrl.add(HandDetectionFrame(
///       landmarks: hand.landmarks.map((p) =>
///           HandLandmarkPoint(p.x, p.y, p.z)).toList(),
///     ));
///   }
///
///   @override
///   Widget buildPreview({double? width, double? height}) =>
///       SizedBox(width: width, height: height, child: CameraPreview(camera));
///
///   @override
///   void dispose() { detector.dispose(); camera.dispose(); _ctrl.close(); }
/// }
/// ```
abstract interface class LandmarkProvider {
  /// Broadcast stream of per-frame hand landmark data.
  ///
  /// Emit one [HandDetectionFrame] per inference step, whether or not a hand
  /// is detected. An empty-landmark frame drives the grace / lost states of
  /// [HandGestureRecognizer]. The stream must be a broadcast stream.
  Stream<HandDetectionFrame> get frames;

  /// Widget that displays the live camera preview.
  ///
  /// [GestureInputSource.buildCameraPreview] delegates here, so the widget
  /// should fill the given [width] and [height].
  Widget buildPreview({double? width, double? height});

  /// Releases all resources held by this provider.
  ///
  /// Called by [GestureInputSource.dispose]; do not call separately.
  void dispose();
}
