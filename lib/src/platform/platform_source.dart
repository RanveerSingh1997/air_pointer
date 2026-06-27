import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/mouse/mouse_input_source.dart';
import 'package:air_pointer/src/stylus/stylus_input_source.dart';
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
/// For stylus-capable desktop/web surfaces (Wacom, Surface Pro, iPad with
/// external keyboard) prefer [defaultPointerSources] which also includes
/// [StylusInputSource].
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

/// Returns the full set of [CanvasInputSource]s appropriate for the current
/// platform.
///
/// | Platform | Returned sources |
/// |---|---|
/// | Android, iOS | `[TouchInputSource]` |
/// | Web, desktop, all others | `[StylusInputSource, MouseInputSource]` |
///
/// On desktop and web both sources are included so that:
/// - Stylus devices (Apple Pencil on iPad web, Wacom tablets, Surface Pen)
///   get pressure-sensitive Down/Move/Up events via [StylusInputSource].
/// - Mouse and trackpad input continues to work via [MouseInputSource].
///
/// [StylusInputSource] filters to stylus-kind events only, so there is no
/// duplication with [MouseInputSource] when both sources are active.
///
/// Use [defaultPointerSource] instead if you only need a single source and
/// do not have stylus users.
///
/// ```dart
/// final controller = CanvasInputController(
///   sources: defaultPointerSources(),
/// );
/// ```
List<CanvasInputSource> defaultPointerSources() {
  if (kIsWeb) return [StylusInputSource(), MouseInputSource()];
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => [TouchInputSource()],
    _ => [StylusInputSource(), MouseInputSource()],
  };
}
