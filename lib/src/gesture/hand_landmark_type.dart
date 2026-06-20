import 'package:air_pointer/src/gesture/hand_landmark_point.dart';

/// The 21 landmarks returned by MediaPipe HandLandmarker, in index order.
///
/// Each case's [index] value equals the corresponding MediaPipe landmark index,
/// so `landmarks.getLandmark(HandLandmarkType.thumbTip)` is equivalent to
/// `landmarks[4]` but self-documenting and safe from off-by-one errors.
enum HandLandmarkType {
  wrist,      // 0
  thumbCmc,   // 1
  thumbMcp,   // 2
  thumbIp,    // 3
  thumbTip,   // 4
  indexMcp,   // 5
  indexPip,   // 6
  indexDip,   // 7
  indexTip,   // 8
  middleMcp,  // 9
  middlePip,  // 10
  middleDip,  // 11
  middleTip,  // 12
  ringMcp,    // 13
  ringPip,    // 14
  ringDip,    // 15
  ringTip,    // 16
  pinkyMcp,   // 17
  pinkyPip,   // 18
  pinkyDip,   // 19
  pinkyTip,   // 20
}

/// Typed access into a 21-point MediaPipe landmark list.
extension HandLandmarkList on List<HandLandmarkPoint> {
  /// Returns the landmark at the position corresponding to [type].
  ///
  /// The list must have at least 21 elements (i.e. [HandGestureRecognizer]'s
  /// length guard has already passed).
  HandLandmarkPoint getLandmark(HandLandmarkType type) => this[type.index];
}
