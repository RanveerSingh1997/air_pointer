import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/widgets.dart';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({void Function(Object, StackTrace)? onError});

  @override
  Stream<PointerInputEvent> get events => const Stream.empty();

  @override
  Widget buildSurface({required Widget child}) => child;

  @override
  void dispose() {}

  // ignore: use_setters_to_change_properties
  void updateCanvasSize(Size size) {}

  Future<void> initialize() async {}

  Widget buildCameraPreview({double? width, double? height}) =>
      const SizedBox.shrink();
}
