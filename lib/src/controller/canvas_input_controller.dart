import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/widgets.dart';

final class CanvasInputController {
  CanvasInputController({
    required List<CanvasInputSource> sources,
    Set<CanvasInputSource>? muteWhenActive,
    Stream<bool>? activeStream,
  })  : _sources = List.unmodifiable(sources),
        _muteWhenActive = muteWhenActive {
    if ((muteWhenActive == null) != (activeStream == null)) {
      throw ArgumentError(
        'Provide both muteWhenActive and activeStream, or neither.',
      );
    }
    if (activeStream != null) {
      _suppressionSub = activeStream.listen(
        (active) => _suppressed = active,
        onError: (Object _, StackTrace _) {},
      );
    }
    _merge();
  }

  final List<CanvasInputSource> _sources;
  final Set<CanvasInputSource>? _muteWhenActive;
  final StreamController<PointerInputEvent> _merged =
      StreamController.broadcast();
  final List<StreamSubscription<PointerInputEvent>> _subscriptions = [];

  bool _suppressed = false;
  StreamSubscription<bool>? _suppressionSub;

  Stream<PointerInputEvent> get events => _merged.stream;

  void _merge() {
    for (final source in _sources) {
      final isMuted = _muteWhenActive?.contains(source) ?? false;
      _subscriptions.add(
        source.events
            .where((_) => !isMuted || !_suppressed)
            .listen(_merged.add, onError: _merged.addError),
      );
    }
  }

  /// Wraps [child] with all source surfaces.
  ///
  /// `sources[0]` is innermost (closest to the canvas widget);
  /// later sources wrap further out. Sources like [GestureInputSource] that
  /// do not need a widget surface return [child] unchanged and add no layers.
  Widget buildSurface({required Widget child}) => _sources.fold<Widget>(
        child,
        (wrapped, source) => source.buildSurface(child: wrapped),
      );

  Future<void> dispose() async {
    await _suppressionSub?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _merged.close();
    for (final source in _sources) {
      source.dispose();
    }
  }
}
