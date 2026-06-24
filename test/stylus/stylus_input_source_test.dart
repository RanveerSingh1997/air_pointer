import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _build(StylusInputSource source) => Directionality(
      textDirection: TextDirection.ltr,
      child: source.buildSurface(
        child: const SizedBox.expand(),
      ),
    );

const _kCenter = Offset(400, 300);

Future<List<PointerInputEvent>> _collect(
  WidgetTester tester,
  StylusInputSource source,
  Future<void> Function() action,
) async {
  final collected = <PointerInputEvent>[];
  final sub = source.events.listen(collected.add);
  await action();
  await tester.pump();
  unawaited(sub.cancel());
  return collected;
}

void main() {
  group('StylusInputSource', () {
    late StylusInputSource source;

    setUp(() {
      source = StylusInputSource();
    });

    tearDown(() {
      source.dispose();
    });

    group('pen drag → Down/Move/Up', () {
      testWidgets('emits CanvasDownEvent, CanvasMoveEvent, CanvasUpEvent',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture = await tester.startGesture(
            _kCenter,
            kind: PointerDeviceKind.stylus,
          );
          await gesture.moveBy(const Offset(50, 0));
          await tester.pump();
          await gesture.up();
        });

        expect(events.whereType<CanvasDownEvent>(), hasLength(1));
        expect(events.whereType<CanvasMoveEvent>(), isNotEmpty);
        expect(events.whereType<CanvasUpEvent>(), hasLength(1));
        expect(events.whereType<CanvasTapEvent>(), isEmpty);
      });

      testWidgets('CanvasDownEvent carries hardware pressure', (tester) async {
        await tester.pumpWidget(_build(source));

        final collected = <PointerInputEvent>[];
        final sub = source.events.listen(collected.add);

        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: 1,
            position: _kCenter,
            kind: PointerDeviceKind.stylus,
            pressure: 0.6,
          ),
        );
        await tester.pump();
        // Clean up the pointer
        await tester.sendEventToBinding(
          const PointerUpEvent(pointer: 1, position: _kCenter),
        );
        unawaited(sub.cancel());

        final down = collected.whereType<CanvasDownEvent>().first;
        expect(down.pressure, closeTo(0.6, 0.01));
      });

      testWidgets('CanvasMoveEvent carries hardware pressure', (tester) async {
        await tester.pumpWidget(_build(source));

        final collected = <PointerInputEvent>[];
        final sub = source.events.listen(collected.add);

        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: 1,
            position: _kCenter,
            kind: PointerDeviceKind.stylus,
          ),
        );
        await tester.sendEventToBinding(
          const PointerMoveEvent(
            pointer: 1,
            position: Offset(450, 300),
            kind: PointerDeviceKind.stylus,
            pressure: 0.75,
          ),
        );
        await tester.pump();
        await tester.sendEventToBinding(
          const PointerUpEvent(pointer: 1, position: Offset(450, 300)),
        );
        unawaited(sub.cancel());

        final move = collected.whereType<CanvasMoveEvent>().first;
        expect(move.pressure, closeTo(0.75, 0.01));
      });
    });

    group('tap detection', () {
      testWidgets('minimal press emits CanvasTapEvent, not CanvasUpEvent',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture = await tester.startGesture(
            _kCenter,
            kind: PointerDeviceKind.stylus,
          );
          await gesture.up(); // no movement — within tapSlop
        });

        expect(events.whereType<CanvasTapEvent>(), hasLength(1));
        expect(events.whereType<CanvasUpEvent>(), isEmpty);
      });

      testWidgets('tap position matches pen-down location', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture = await tester.startGesture(
            _kCenter,
            kind: PointerDeviceKind.stylus,
          );
          await gesture.up();
        });

        final tap = events.whereType<CanvasTapEvent>().first;
        expect(tap.position.dx, closeTo(_kCenter.dx, 5));
        expect(tap.position.dy, closeTo(_kCenter.dy, 5));
      });

      testWidgets('two taps within doubleTapWindow emit double-tap',
          (tester) async {
        final fastSource = StylusInputSource(
          doubleTapWindow: const Duration(milliseconds: 500),
        );
        addTearDown(fastSource.dispose);
        await tester.pumpWidget(_build(fastSource));

        final events = <PointerInputEvent>[];
        final sub = fastSource.events.listen(events.add);

        final g1 = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await g1.up();
        await tester.pump(const Duration(milliseconds: 100));
        final g2 = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await g2.up();
        await tester.pump();
        unawaited(sub.cancel());

        expect(events.whereType<CanvasTapEvent>(), hasLength(2));
        expect(events.whereType<CanvasDoubleTapEvent>(), hasLength(1));
      });

      testWidgets('third tap after double-tap does not fire second double-tap',
          (tester) async {
        final fastSource = StylusInputSource(
          doubleTapWindow: const Duration(milliseconds: 500),
        );
        addTearDown(fastSource.dispose);
        await tester.pumpWidget(_build(fastSource));

        final events = <PointerInputEvent>[];
        final sub = fastSource.events.listen(events.add);

        final g1 = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await g1.up();
        final g2 = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await g2.up(); // double-tap fires, resets _lastTapTime
        final g3 = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await g3.up(); // starts fresh window — no second double-tap
        await tester.pump();
        unawaited(sub.cancel());

        expect(events.whereType<CanvasDoubleTapEvent>(), hasLength(1));
      });
    });

    group('hover', () {
      testWidgets('stylus PointerHoverEvent emits CanvasHoverEvent',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final collected = <PointerInputEvent>[];
        final sub = source.events.listen(collected.add);
        await tester.sendEventToBinding(
          const PointerHoverEvent(
            position: _kCenter,
            kind: PointerDeviceKind.stylus,
          ),
        );
        await tester.pump();
        unawaited(sub.cancel());

        expect(collected.whereType<CanvasHoverEvent>(), hasLength(1));
      });

      testWidgets('mouse PointerHoverEvent is filtered out', (tester) async {
        await tester.pumpWidget(_build(source));

        final collected = <PointerInputEvent>[];
        final sub = source.events.listen(collected.add);
        await tester.sendEventToBinding(
          const PointerHoverEvent(
            position: _kCenter,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pump();
        unawaited(sub.cancel());

        expect(collected, isEmpty);
      });
    });

    group('non-stylus events filtered', () {
      testWidgets('mouse drag does not emit canvas drag events', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture = await tester.startGesture(
            _kCenter,
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(50, 0));
          await gesture.up();
        });

        expect(events.whereType<CanvasDownEvent>(), isEmpty);
        expect(events.whereType<CanvasMoveEvent>(), isEmpty);
        expect(events.whereType<CanvasUpEvent>(), isEmpty);
        expect(events.whereType<CanvasTapEvent>(), isEmpty);
      });
    });

    group('eraser mode stream', () {
      testWidgets('pen tip contact emits false on first use', (tester) async {
        await tester.pumpWidget(_build(source));

        final modes = <bool>[];
        final sub = source.eraserModeStream.listen(modes.add);

        final gesture = await tester.startGesture(
          _kCenter,
          kind: PointerDeviceKind.stylus,
        );
        await gesture.up();
        await tester.pump();
        unawaited(sub.cancel());

        expect(modes, equals([false]));
      });

      testWidgets('invertedStylus contact emits true', (tester) async {
        await tester.pumpWidget(_build(source));

        final modes = <bool>[];
        final sub = source.eraserModeStream.listen(modes.add);

        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: 1,
            position: _kCenter,
            kind: PointerDeviceKind.invertedStylus,
          ),
        );
        await tester.pump();
        await tester.sendEventToBinding(
          const PointerUpEvent(pointer: 1, position: _kCenter),
        );
        await tester.pump();
        unawaited(sub.cancel());

        expect(modes, contains(true));
      });

      testWidgets('no duplicate emissions for consecutive same-mode contacts',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final modes = <bool>[];
        final sub = source.eraserModeStream.listen(modes.add);

        // Two pen-tip contacts in sequence — eraser mode stays false
        for (var i = 0; i < 2; i++) {
          final gesture = await tester.startGesture(
            _kCenter,
            kind: PointerDeviceKind.stylus,
          );
          await gesture.up();
          await tester.pump();
        }
        unawaited(sub.cancel());

        // First contact emits false; second is suppressed (same mode)
        expect(modes, equals([false]));
      });
    });

    group('cancel', () {
      testWidgets('PointerCancelEvent emits CanvasCancelEvent', (tester) async {
        await tester.pumpWidget(_build(source));

        final collected = <PointerInputEvent>[];
        final sub = source.events.listen(collected.add);

        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: 1,
            position: _kCenter,
            kind: PointerDeviceKind.stylus,
          ),
        );
        await tester.pump();
        await tester.sendEventToBinding(
          const PointerCancelEvent(pointer: 1, position: _kCenter),
        );
        await tester.pump();
        unawaited(sub.cancel());

        expect(collected.whereType<CanvasCancelEvent>(), hasLength(1));
      });
    });

    group('dispose', () {
      testWidgets('dispose closes stream without error', (tester) async {
        final local = StylusInputSource();
        await tester.pumpWidget(_build(local));
        expect(() => local.dispose(), returnsNormally);
      });
    });
  });
}
