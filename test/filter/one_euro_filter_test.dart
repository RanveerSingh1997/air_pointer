import 'package:air_pointer/air_pointer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OneEuroFilter', () {
    test('converges toward true value', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.05);
      const dt = 1 / 30.0;
      const trueValue = 100.0;

      double output = 0;
      for (var i = 0; i < 60; i++) {
        output = filter.filter(trueValue, dt);
      }

      expect(output, closeTo(trueValue, 1.0));
    });

    test('reduces noise on noisy signal', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.0);
      const dt = 1 / 30.0;

      final noisy = [100.0, 101.5, 99.5, 100.2, 100.8, 99.8, 100.1, 100.0];
      double prev = 0;
      double totalVariationNoisy = 0;
      double totalVariationFiltered = 0;
      double prevFiltered = 0;

      for (var i = 0; i < noisy.length; i++) {
        final filtered = filter.filter(noisy[i], dt);
        if (i > 0) {
          totalVariationNoisy += (noisy[i] - prev).abs();
          totalVariationFiltered += (filtered - prevFiltered).abs();
        }
        prev = noisy[i];
        prevFiltered = filtered;
      }

      expect(totalVariationFiltered, lessThan(totalVariationNoisy));
    });

    test('returns initial value on first call', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.05);
      final result = filter.filter(42.0, 1 / 30.0);
      expect(result, closeTo(42.0, 1.0));
    });
  });
}
