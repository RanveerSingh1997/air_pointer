import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

/// Dialog that walks the user through a ~5-second pinch calibration and applies
/// the resulting [CalibrationResult] to [source] when complete.
///
/// Show with:
/// ```dart
/// await showDialog<void>(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => CalibrationDialog(source: _gestureSource),
/// );
/// ```
class CalibrationDialog extends StatefulWidget {
  const CalibrationDialog({required this.source, super.key});

  final GestureInputSource source;

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

enum _Step { waitForHand, collectOpen, collectClose, done, failed }

class _CalibrationDialogState extends State<CalibrationDialog> {
  final _calibrator = GestureCalibrator();
  StreamSubscription<GestureDebugInfo>? _sub;
  _Step _step = _Step.waitForHand;
  CalibrationResult? _result;

  // Filter param state — initialised from recognizer defaults.
  double _minCutoff = 1.0;
  double _beta = 0.05;

  @override
  void initState() {
    super.initState();
    _sub = widget.source.debugInfo.listen(_onFrame);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onFrame(GestureDebugInfo info) {
    if (!mounted) return;
    setState(() {
      switch (_step) {
        case _Step.waitForHand:
          final tracked = info.phase != GesturePhase.lost &&
              info.phase != GesturePhase.acquiring;
          if (tracked) _step = _Step.collectOpen;

        case _Step.collectOpen:
          if (info.phase == GesturePhase.lost) {
            // Lost tracking — reset and wait again.
            _calibrator.reset();
            _step = _Step.waitForHand;
            return;
          }
          _calibrator.addOpenSample(info.pinchDistance);
          if (_calibrator.openDone) _step = _Step.collectClose;

        case _Step.collectClose:
          if (info.phase == GesturePhase.lost) return;  // tolerate brief loss
          _calibrator.addCloseSample(info.pinchDistance);
          if (_calibrator.closeDone) {
            final result = _calibrator.compute();
            if (result != null) {
              _result = result;
              widget.source.applyCalibration(result);
              _step = _Step.done;
            } else {
              _step = _Step.failed;
            }
          }

        case _Step.done:
        case _Step.failed:
          break;
      }
    });
  }

  void _restart() {
    setState(() {
      _calibrator.reset();
      _result = null;
      _step = _Step.waitForHand;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title row
                Row(
                  children: [
                    const Icon(Icons.tune_rounded,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Hand Calibration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close,
                          color: Colors.white54, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Camera preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.source
                      .buildCameraPreview(width: 252, height: 142),
                ),
                const SizedBox(height: 20),

                // Step content
                _buildStepContent(),
                const SizedBox(height: 20),

                // Action buttons
                _buildActions(context),
                const SizedBox(height: 20),

                // Filter tuning
                _buildFilterSection(),
              ],
            ),
          ),
        ),
      );

  Widget _buildStepContent() {
    return switch (_step) {
      _Step.waitForHand => const _StepCard(
          icon: Icons.back_hand_outlined,
          text: 'Show your hand to the camera',
          subtext: 'Waiting for hand detection…',
          color: Colors.white54,
          showProgress: false,
          progress: 0,
        ),
      _Step.collectOpen => _StepCard(
          icon: Icons.pan_tool_outlined,
          text: 'Hold your hand open',
          subtext: 'Keep fingers spread for 2 seconds',
          color: Colors.greenAccent,
          showProgress: true,
          progress: _calibrator.openProgress,
        ),
      _Step.collectClose => _StepCard(
          icon: Icons.pinch_outlined,
          text: 'Pinch thumb and index together',
          subtext: 'Hold the pinch steady for 2 seconds',
          color: Colors.orangeAccent,
          showProgress: true,
          progress: _calibrator.closeProgress,
        ),
      _Step.done => _ResultCard(result: _result!),
      _Step.failed => const _StepCard(
          icon: Icons.warning_amber_rounded,
          text: 'Could not distinguish poses',
          subtext: 'Try adjusting lighting or moving closer',
          color: Colors.redAccent,
          showProgress: false,
          progress: 0,
        ),
    };
  }

  Widget _buildFilterSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),
          const Text(
            'Cursor smoothing',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _FilterSlider(
            label: 'Smoothing',
            hint: 'Low = smoother, High = more responsive',
            value: _minCutoff,
            min: 0.2,
            max: 5.0,
            divisions: 48,
            format: (v) => '${v.toStringAsFixed(1)} Hz',
            onChanged: (v) {
              setState(() => _minCutoff = v);
              widget.source.setFilterParams(minCutoff: v, beta: _beta);
            },
          ),
          const SizedBox(height: 8),
          _FilterSlider(
            label: 'Speed adapt',
            hint: 'Higher = less lag on fast motion',
            value: _beta,
            min: 0.0,
            max: 0.5,
            divisions: 50,
            format: (v) => v.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _beta = v);
              widget.source.setFilterParams(minCutoff: _minCutoff, beta: v);
            },
          ),
        ],
      );

  Widget _buildActions(BuildContext context) {
    if (_step == _Step.done) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      );
    }
    if (_step == _Step.failed) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white24)),
              child: const Text('Skip'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _restart,
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white54,
            side: const BorderSide(color: Colors.white24)),
        child: const Text('Skip'),
      ),
    );
  }
}

// ── Step instruction card ─────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.text,
    required this.subtext,
    required this.color,
    required this.showProgress,
    required this.progress,
  });

  final IconData icon;
  final String text;
  final String subtext;
  final Color color;
  final bool showProgress;
  final double progress;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (showProgress) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white12,
                color: color,
                minHeight: 6,
              ),
            ),
          ],
        ],
      );
}

// ── Calibration result card ───────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final CalibrationResult result;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Colors.greenAccent, size: 32),
          const SizedBox(height: 10),
          const Text(
            'Calibration complete',
            style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Threshold(
                    label: 'close',
                    value: result.pinchCloseThreshold,
                    color: Colors.redAccent),
                _Threshold(
                    label: 'open',
                    value: result.pinchOpenThreshold,
                    color: Colors.greenAccent),
              ],
            ),
          ),
        ],
      );
}

class _Threshold extends StatelessWidget {
  const _Threshold(
      {required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
}

// ── Filter parameter slider ───────────────────────────────────────────────────

class _FilterSlider extends StatelessWidget {
  const _FilterSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const Spacer(),
              Text(
                format(value),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white54,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white10,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Text(
            hint,
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
        ],
      );
}
