import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/widgets.dart';

abstract interface class CanvasInputSource {
  Stream<PointerInputEvent> get events;

  /// Wraps [child] with the platform-specific event-listening surface.
  ///
  /// Sources that capture events off-widget (e.g. camera via JS callbacks)
  /// return [child] unchanged.
  Widget buildSurface({required Widget child});

  void dispose();
}
