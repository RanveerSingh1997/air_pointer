import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultPointerSource', () {
    test('returns a CanvasInputSource', () {
      final source = defaultPointerSource();
      expect(source, isA<CanvasInputSource>());
      source.dispose();
    });

    test('returned source exposes an events stream', () {
      final source = defaultPointerSource();
      expect(source.events, isA<Stream<PointerInputEvent>>());
      source.dispose();
    });

    test('returns TouchInputSource on Android and iOS', () {
      // Simulate mobile platform by overriding debugDefaultTargetPlatformOverride.
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final source = defaultPointerSource();
        expect(
          source,
          isA<TouchInputSource>(),
          reason: 'expected TouchInputSource on $platform',
        );
        source.dispose();
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('returns MouseInputSource on desktop and web platforms', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final source = defaultPointerSource();
        expect(
          source,
          isA<MouseInputSource>(),
          reason: 'expected MouseInputSource on $platform',
        );
        source.dispose();
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('returned source builds a valid surface widget', (tester) async {
      final source = defaultPointerSource();
      addTearDown(source.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: source.buildSurface(child: const SizedBox.expand()),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('defaultPointerSources', () {
    test('returns TouchInputSource on Android and iOS', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final sources = defaultPointerSources();
        expect(sources, hasLength(1));
        expect(sources.first, isA<TouchInputSource>());
        for (final s in sources) {
          s.dispose();
        }
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('returns StylusInputSource + MouseInputSource on desktop', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final sources = defaultPointerSources();
        expect(sources, hasLength(2));
        expect(sources[0], isA<StylusInputSource>());
        expect(sources[1], isA<MouseInputSource>());
        for (final s in sources) {
          s.dispose();
        }
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('each returned source exposes an events stream', () {
      final sources = defaultPointerSources();
      for (final s in sources) {
        expect(s.events, isA<Stream<PointerInputEvent>>());
        s.dispose();
      }
    });
  });
}
