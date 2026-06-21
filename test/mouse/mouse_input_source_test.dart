import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal widget — no MaterialApp/Navigator so there are no pending page
// transition animations that would block TestAsyncUtils.guard.
Widget _build(MouseInputSource source) => Directionality(
      textDirection: TextDirection.ltr,
      child: source.buildSurface(
        child: const SizedBox.expand(),
      ),
    );

// Center of the default 800×600 test viewport.
const _kCenter = Offset(400, 300);

// Subscribes to [source.events], dispatches [event] via sendEventToBinding,
// pumps one frame to flush microtasks, then cancels the subscription.
Future<List<PointerInputEvent>> _sendSignal(
  WidgetTester tester,
  MouseInputSource source,
  PointerSignalEvent event,
) async {
  final collected = <PointerInputEvent>[];
  final sub = source.events.listen(collected.add);
  await tester.sendEventToBinding(event);
  await tester.pump(); // flush broadcast-stream microtask delivery
  unawaited(sub.cancel()); // source.dispose() in tearDown closes the stream
  return collected;
}

void main() {
  group('MouseInputSource', () {
    late MouseInputSource source;

    setUp(() {
      source = MouseInputSource();
    });

    tearDown(() {
      source.dispose();
    });

    group('scroll', () {
      testWidgets('PointerScrollEvent emits CanvasScrollEvent', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _sendSignal(
          tester,
          source,
          const PointerScrollEvent(position: _kCenter, scrollDelta: Offset(0, 100)),
        );

        expect(events, hasLength(1));
        final scroll = events.first as CanvasScrollEvent;
        expect(scroll.delta.dy, 100);
        expect(scroll.isTrackpad, isFalse);
      });

      testWidgets('trackpad scroll sets isTrackpad=true', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _sendSignal(
          tester,
          source,
          const PointerScrollEvent(
            position: _kCenter,
            scrollDelta: Offset(0, 10),
            kind: PointerDeviceKind.trackpad,
          ),
        );

        expect(events, hasLength(1));
        expect((events.first as CanvasScrollEvent).isTrackpad, isTrue);
      });

      testWidgets('scrollMultiplier scales the delta', (tester) async {
        final scaledSource = MouseInputSource(scrollMultiplier: 2.0);
        addTearDown(scaledSource.dispose);
        await tester.pumpWidget(_build(scaledSource));

        final events = await _sendSignal(
          tester,
          scaledSource,
          const PointerScrollEvent(position: _kCenter, scrollDelta: Offset(0, 50)),
        );

        final scroll = events.first as CanvasScrollEvent;
        expect(scroll.delta.dy, closeTo(100, 1e-9));
      });
    });

    group('native trackpad pinch (PointerScaleEvent)', () {
      testWidgets('emits CanvasScaleEvent followed by CanvasScaleEndEvent',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _sendSignal(
          tester,
          source,
          const PointerScaleEvent(
            position: _kCenter,
            scale: 1.1,
            kind: PointerDeviceKind.trackpad,
          ),
        );

        expect(events, hasLength(2));
        final scale = events[0] as CanvasScaleEvent;
        expect(scale.scaleDelta, closeTo(1.1, 1e-9));
        expect(scale.panDelta, Offset.zero);
        expect(events[1], isA<CanvasScaleEndEvent>());
      });

      testWidgets('zoom-out: scaleDelta < 1.0 is preserved', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _sendSignal(
          tester,
          source,
          const PointerScaleEvent(
            position: _kCenter,
            scale: 0.9,
            kind: PointerDeviceKind.trackpad,
          ),
        );

        final scale = events.first as CanvasScaleEvent;
        expect(scale.scaleDelta, closeTo(0.9, 1e-9));
      });
    });

    group('dispose', () {
      testWidgets('dispose closes stream without error', (tester) async {
        final local = MouseInputSource();
        await tester.pumpWidget(_build(local));
        expect(() => local.dispose(), returnsNormally);
      });
    });
  });
}
