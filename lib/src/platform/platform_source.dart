import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/mouse/mouse_input_source.dart';
import 'package:air_pointer/src/touch/touch_input_source.dart';
import 'package:flutter/foundation.dart';

/// Returns the best-fit [CanvasInputSource] for the current runtime platform.
///
/// | Platform | Returned source |
/// |---|---|
/// | Android, iOS | [TouchInputSource] |
/// | Web, desktop, all others | [MouseInputSource] |
///
/// Use this when you want a single-line setup and do not need to customise
/// pointer-source parameters:
///
/// ```dart
/// final controller = CanvasInputController(
///   sources: [defaultPointerSource()],
/// );
/// ```
///
/// [GestureInputSource] is intentionally not included — it requires
/// platform-specific configuration ([mediaPipeBaseUrl], [LandmarkProvider],
/// dwell settings, etc.) that cannot be inferred automatically. Add it to
/// your sources list separately if you need air-gesture input.
///
/// Uses [kIsWeb] and [defaultTargetPlatform] (from `package:flutter/foundation.dart`)
/// rather than `dart:io`'s `Platform`, so it is safe to call on web.
CanvasInputSource defaultPointerSource() {
  if (kIsWeb) return MouseInputSource();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => TouchInputSource(),
    _ => MouseInputSource(),
  };
}
