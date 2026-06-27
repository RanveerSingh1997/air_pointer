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

/// Skeleton connections for the 21-point MediaPipe hand landmark topology.
///
/// Each entry is a pair `[start, end]` identifying the two landmarks that form
/// one bone segment of the hand skeleton. Iterate over this list to draw a
/// skeleton overlay, e.g.:
///
/// ```dart
/// for (final connection in handLandmarkConnections) {
///   final start = landmarks.getLandmark(connection[0]);
///   final end   = landmarks.getLandmark(connection[1]);
///   canvas.drawLine(Offset(start.x, start.y), Offset(end.x, end.y), paint);
/// }
/// ```
const List<List<HandLandmarkType>> handLandmarkConnections = [
  // Thumb
  [HandLandmarkType.wrist,     HandLandmarkType.thumbCmc],
  [HandLandmarkType.thumbCmc,  HandLandmarkType.thumbMcp],
  [HandLandmarkType.thumbMcp,  HandLandmarkType.thumbIp],
  [HandLandmarkType.thumbIp,   HandLandmarkType.thumbTip],
  // Index finger
  [HandLandmarkType.wrist,     HandLandmarkType.indexMcp],
  [HandLandmarkType.indexMcp,  HandLandmarkType.indexPip],
  [HandLandmarkType.indexPip,  HandLandmarkType.indexDip],
  [HandLandmarkType.indexDip,  HandLandmarkType.indexTip],
  // Middle finger
  [HandLandmarkType.indexMcp,  HandLandmarkType.middleMcp],
  [HandLandmarkType.middleMcp, HandLandmarkType.middlePip],
  [HandLandmarkType.middlePip, HandLandmarkType.middleDip],
  [HandLandmarkType.middleDip, HandLandmarkType.middleTip],
  // Ring finger
  [HandLandmarkType.middleMcp, HandLandmarkType.ringMcp],
  [HandLandmarkType.ringMcp,   HandLandmarkType.ringPip],
  [HandLandmarkType.ringPip,   HandLandmarkType.ringDip],
  [HandLandmarkType.ringDip,   HandLandmarkType.ringTip],
  // Pinky
  [HandLandmarkType.ringMcp,   HandLandmarkType.pinkyMcp],
  [HandLandmarkType.pinkyMcp,  HandLandmarkType.pinkyPip],
  [HandLandmarkType.pinkyPip,  HandLandmarkType.pinkyDip],
  [HandLandmarkType.pinkyDip,  HandLandmarkType.pinkyTip],
  // Outer palm edge
  [HandLandmarkType.wrist,     HandLandmarkType.pinkyMcp],
];

/// Typed access into a 21-point MediaPipe landmark list.
extension HandLandmarkList on List<HandLandmarkPoint> {
  /// Returns the landmark at the position corresponding to [type].
  ///
  /// The list must have at least 21 elements (i.e. [HandGestureRecognizer]'s
  /// length guard has already passed).
  HandLandmarkPoint getLandmark(HandLandmarkType type) => this[type.index];
}
