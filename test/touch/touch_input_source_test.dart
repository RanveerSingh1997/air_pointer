import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _build(TouchInputSource source) => Directionality(
      textDirection: TextDirection.ltr,
      child: source.buildSurface(
        child: const SizedBox.expand(),
      ),
    );

const _kCenter = Offset(400, 300);

// TouchInputSource uses raw Listener.onPointerDown/Up for tap detection so
// tester.tapAt() works directly — no GestureDetector arena needed.
Future<void> _simulateTap(WidgetTester tester, Offset at) =>
    tester.tapAt(at);

/// Pumps [action] while collecting [source.events].
Future<List<PointerInputEvent>> _collect(
  WidgetTester tester,
  TouchInputSource source,
  Future<void> Function() action,
) async {
  final collected = <PointerInputEvent>[];
  final sub = source.events.listen(collected.add);
  await action();
  await tester.pumpAndSettle();
  unawaited(sub.cancel());
  return collected;
}

void main() {
  group('TouchInputSource', () {
    late TouchInputSource source;

    setUp(() {
      source = TouchInputSource();
    });

    tearDown(() {
      source.dispose();
    });

    group('single-finger drag → CanvasScrollEvent', () {
      testWidgets('emits CanvasScrollEvent, not CanvasDownEvent', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.dragFrom(_kCenter, const Offset(100, 0)),
        );

        expect(events.whereType<CanvasDownEvent>(), isEmpty);
        expect(events.whereType<CanvasScrollEvent>(), isNotEmpty);
      });

      testWidgets('rightward drag produces negative delta.dx', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.dragFrom(_kCenter, const Offset(80, 0)),
        );

        final scrolls = events.whereType<CanvasScrollEvent>().toList();
        final totalDx = scrolls.fold(0.0, (s, e) => s + e.delta.dx);
        // Rightward drag → negative dx so consumers doing offset -= delta pan right
        expect(totalDx, lessThan(0));
      });

      testWidgets('downward drag produces negative delta.dy', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.dragFrom(_kCenter, const Offset(0, 60)),
        );

        final scrolls = events.whereType<CanvasScrollEvent>().toList();
        final totalDy = scrolls.fold(0.0, (s, e) => s + e.delta.dy);
        expect(totalDy, lessThan(0));
      });

      testWidgets('isTrackpad is always false', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.dragFrom(_kCenter, const Offset(50, 0)),
        );

        for (final e in events.whereType<CanvasScrollEvent>()) {
          expect(e.isTrackpad, isFalse);
        }
      });

      testWidgets('slow drag events have zero velocity', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.dragFrom(_kCenter, const Offset(50, 0)),
        );

        // tester.drag ends with zero velocity — no fling event expected
        for (final e in events.whereType<CanvasScrollEvent>()) {
          expect(e.velocity, Offset.zero);
        }
      });
    });

    group('fling → CanvasScrollEvent with velocity', () {
      testWidgets('fast drag emits a fling event with non-zero velocity',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.flingFrom(_kCenter, const Offset(200, 0), 2000),
        );

        final flings = events
            .whereType<CanvasScrollEvent>()
            .where((e) => e.velocity != Offset.zero)
            .toList();
        expect(flings, hasLength(1));
        // Velocity is in finger-movement direction: rightward fling → dx > 0
        expect(flings.first.velocity.dx, greaterThan(0));
        expect(flings.first.delta, Offset.zero);
      });
    });

    group('tap detection', () {
      testWidgets('sub-tapSlop press emits CanvasTapEvent, not scroll', (tester) async {
        await tester.pumpWidget(_build(source));

        // 2px movement is below the default tapSlop of 10px → tap, not scroll
        final events = await _collect(
          tester,
          source,
          () => _simulateTap(tester, _kCenter),
        );

        expect(events.whereType<CanvasTapEvent>(), hasLength(1));
        expect(events.whereType<CanvasScrollEvent>(), isEmpty);
      });

      testWidgets('tap position is the press location', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => _simulateTap(tester, _kCenter),
        );

        final tap = events.whereType<CanvasTapEvent>().first;
        expect(tap.position.dx, closeTo(_kCenter.dx, 5));
        expect(tap.position.dy, closeTo(_kCenter.dy, 5));
      });

      testWidgets('two taps within doubleTapWindow emit double-tap', (tester) async {
        final fastSource = TouchInputSource(
          doubleTapWindow: const Duration(milliseconds: 500),
        );
        addTearDown(fastSource.dispose);
        await tester.pumpWidget(_build(fastSource));

        final events = <PointerInputEvent>[];
        final sub = fastSource.events.listen(events.add);

        await _simulateTap(tester, _kCenter);
        await tester.pump(const Duration(milliseconds: 100));
        await _simulateTap(tester, _kCenter);
        await tester.pumpAndSettle();
        unawaited(sub.cancel());

        expect(events.whereType<CanvasTapEvent>(), hasLength(2));
        expect(events.whereType<CanvasDoubleTapEvent>(), hasLength(1));
      });

      testWidgets('third tap after double-tap does not fire second double-tap',
          (tester) async {
        // After a double-tap fires, _lastTapTime resets to null so the next
        // single tap starts a fresh window rather than chaining another double.
        final fastSource = TouchInputSource(
          doubleTapWindow: const Duration(milliseconds: 500),
        );
        addTearDown(fastSource.dispose);
        await tester.pumpWidget(_build(fastSource));

        final events = <PointerInputEvent>[];
        final sub = fastSource.events.listen(events.add);

        await _simulateTap(tester, _kCenter); // tap 1
        await _simulateTap(tester, _kCenter); // tap 2 → double-tap fires, resets
        await _simulateTap(tester, _kCenter); // tap 3 → starts fresh, no double-tap
        await tester.pumpAndSettle();
        unawaited(sub.cancel());

        expect(events.whereType<CanvasDoubleTapEvent>(), hasLength(1));
      });
    });

    group('long press', () {
      testWidgets('emits CanvasLongPressEvent', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(
          tester,
          source,
          () => tester.longPressAt(_kCenter),
        );

        expect(events.whereType<CanvasLongPressEvent>(), hasLength(1));
      });
    });

    group('two-finger pinch → CanvasScaleEvent', () {
      testWidgets('pinch emits CanvasScaleEvent and CanvasScaleEndEvent',
          (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture1 = await tester.startGesture(_kCenter - const Offset(50, 0));
          final gesture2 = await tester.startGesture(_kCenter + const Offset(50, 0));
          await tester.pump();
          await gesture1.moveBy(const Offset(-30, 0));
          await gesture2.moveBy(const Offset(30, 0));
          await tester.pump();
          await gesture1.up();
          await gesture2.up();
        });

        expect(events.whereType<CanvasScaleEvent>(), isNotEmpty);
        expect(events.whereType<CanvasScaleEndEvent>(), hasLength(1));
      });

      testWidgets('spread gesture produces scaleDelta > 1', (tester) async {
        await tester.pumpWidget(_build(source));

        final events = await _collect(tester, source, () async {
          final gesture1 = await tester.startGesture(_kCenter - const Offset(20, 0));
          final gesture2 = await tester.startGesture(_kCenter + const Offset(20, 0));
          await tester.pump();
          await gesture1.moveBy(const Offset(-60, 0));
          await gesture2.moveBy(const Offset(60, 0));
          await tester.pump();
          await gesture1.up();
          await gesture2.up();
        });

        final scales = events.whereType<CanvasScaleEvent>().toList();
        expect(scales, isNotEmpty);
        // At least one scale event should show zoom-in (spread)
        expect(scales.any((e) => e.scaleDelta > 1.0), isTrue);
      });
    });

    group('dispose', () {
      testWidgets('dispose closes stream without error', (tester) async {
        final local = TouchInputSource();
        await tester.pumpWidget(_build(local));
        expect(() => local.dispose(), returnsNormally);
      });
    });
  });
}
