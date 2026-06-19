import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements CanvasInputSource {
  _FakeSource() : _controller = StreamController.broadcast();

  final StreamController<PointerInputEvent> _controller;

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) =>
      ColoredBox(color: const Color(0x00000000), child: child);

  @override
  void dispose() => unawaited(_controller.close());

  void emit(PointerInputEvent event) => _controller.add(event);
}

void main() {
  group('CanvasInputController', () {
    test('merges events from multiple sources', () async {
      final a = _FakeSource();
      final b = _FakeSource();
      final controller = CanvasInputController(sources: [a, b]);

      final received = <PointerInputEvent>[];
      final sub = controller.events.listen(received.add);

      a.emit(const CanvasDownEvent(position: Offset(1, 1)));
      b.emit(const CanvasDownEvent(position: Offset(2, 2)));

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));

      await sub.cancel();
      await controller.dispose();
    });

    test('dispose closes merged stream', () async {
      final source = _FakeSource();
      final controller = CanvasInputController(sources: [source]);

      var doneCalled = false;
      controller.events.listen(null, onDone: () => doneCalled = true);

      await controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(doneCalled, isTrue);
    });

    test('buildSurface folds source surfaces', () {
      final a = _FakeSource();
      final b = _FakeSource();
      final controller = CanvasInputController(sources: [a, b]);

      final result = controller.buildSurface(
        child: const SizedBox.shrink(),
      );

      expect(result, isA<ColoredBox>());
    });
  });
}
