/// A single MediaPipe hand landmark, normalised to [0, 1] in each axis.
final class HandLandmarkPoint {
  const HandLandmarkPoint(this.x, this.y, this.z, {this.visibility = 1.0});

  final double x;
  final double y;
  final double z;

  /// Confidence that this landmark is clearly visible in the image (0–1).
  ///
  /// Values close to 0 indicate the landmark is likely occluded or out of
  /// frame. Defaults to 1.0 when not provided by the underlying model.
  final double visibility;
}
