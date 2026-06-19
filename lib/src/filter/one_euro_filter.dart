import 'dart:math' as math;

/// Adaptive low-pass filter for noisy continuous 1D signals.
///
/// Reference: Casiez et al., "1€ Filter: A Simple Speed-based Low-pass Filter
/// for Noisy Input in Interactive Systems" (CHI 2012).
final class OneEuroFilter {
  OneEuroFilter({
    required this.minCutoff,
    required this.beta,
    this.dCutoff = 1.0,
  });

  final double minCutoff;
  final double beta;
  final double dCutoff;

  _LowPassFilter? _xFilter;
  _LowPassFilter? _dxFilter;
  double? _prevValue;

  double filter(double value, double dt) {
    final dx = _prevValue == null ? 0.0 : (value - _prevValue!) / dt;
    _prevValue = value;
    final alphaDx = _alpha(dCutoff, dt);
    _dxFilter ??= _LowPassFilter(initialValue: dx);
    final dxFiltered = _dxFilter!.filter(dx, alphaDx);
    final cutoff = minCutoff + beta * dxFiltered.abs();
    final alpha = _alpha(cutoff, dt);
    _xFilter ??= _LowPassFilter(initialValue: value);
    return _xFilter!.filter(value, alpha);
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }
}

final class _LowPassFilter {
  _LowPassFilter({required double initialValue}) : _prev = initialValue;

  double _prev;

  double filter(double x, double alpha) =>
      _prev = alpha * x + (1 - alpha) * _prev;
}
