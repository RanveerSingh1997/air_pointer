import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/gesture/calibration_result.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_gesture_recognizer.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// Pinned to avoid silent breakage when MediaPipe releases incompatible updates.
const String _kMediaPipeVersion = '0.10.21';
const String _kWasmPath =
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$_kMediaPipeVersion/wasm';
const String _kModelPath =
    'https://storage.googleapis.com/mediapipe-models/'
    'hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({
    this.onError,
    Duration dwellDuration = Duration.zero,
    double dwellRadius = 12.0,
    bool scrollEnabled = false,
    double scrollScale = 3.0,
  }) {
    _recognizer = HandGestureRecognizer(
      dwellDuration: dwellDuration,
      dwellRadius: dwellRadius,
      scrollEnabled: scrollEnabled,
      scrollScale: scrollScale,
    );
  }

  final void Function(Object, StackTrace)? onError;

  final StreamController<PointerInputEvent> _controller =
      StreamController.broadcast();
  final StreamController<GestureDebugInfo> _debugController =
      StreamController.broadcast();

  /// Stream of per-frame debug snapshots: gesture phase, pinch distance,
  /// landmarks, and latency. Use this to drive a debug overlay.
  Stream<GestureDebugInfo> get debugInfo => _debugController.stream;

  web.Worker? _worker;
  web.HTMLVideoElement? _video;
  web.HTMLVideoElement? _previewVideo;
  String? _previewViewType;

  // Completes when the camera stream is live and the preview view is registered.
  final Completer<void> _cameraReady = Completer<void>();

  bool _initialized = false;
  bool _disposed = false;

  // Set while the worker is processing a frame; prevents flooding the worker.
  bool _workerBusy = false;

  Size _canvasSize = Size.zero;

  int _frameCount = 0;
  double _prevTimestampMs = 0;
  int _lastSendMs = 0;  // wall-clock ms when the last frame was posted

  late final HandGestureRecognizer _recognizer;
  // Cached JS wrapper — .toJS allocates a new object each call, so caching
  // prevents one GC-able allocation per rAF tick (60/s in the hot path).
  late final JSFunction _captureLoopJS = _captureLoop.toJS;

  void updateCanvasSize(Size size) => _canvasSize = size;

  /// Applies per-user detection thresholds from a completed calibration.
  ///
  /// Safe to call at any time; takes effect on the next processed frame.
  void applyCalibration(CalibrationResult result) =>
      _recognizer.setThresholds(result);

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    // Fast-fail for insecure context before attempting getUserMedia. Browsers
    // block camera access on plain HTTP outside localhost.
    if (!web.window.isSecureContext) {
      _initialized = false;
      final err = StateError(
        'Camera not available — serve the page over HTTPS or localhost.',
      );
      if (!_cameraReady.isCompleted) _cameraReady.completeError(err);
      onError?.call(err, StackTrace.current);
      return;
    }

    try {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..autoplay = true
        ..muted = true     // required by browsers for autoplay without a user gesture
        ..playsInline = true
        ..style.display = 'none';
      web.document.body?.appendChild(video);
      _video = video;

      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(video: true.toJS, audio: false.toJS),
          )
          .toDart;
      if (_disposed) return;

      video.srcObject = stream;
      await video.play().toDart;  // await — autoplay attribute alone is unreliable
      if (_disposed) return;

      // Camera is live. Register the preview view — this completes _cameraReady.
      _setupPreview(stream);

      // Spin up the inference worker. MediaPipe is loaded inside the worker
      // (via its own ES module import) so the main thread stays clean.
      // Classic worker (no type:'module') so MediaPipe's WASM runtime can
      // call importScripts() for its internal sub-worker threads.
      _worker = web.Worker('hand_tracker_worker.js'.toJS);
      _worker!.onmessage = _onWorkerMessage.toJS;
      _worker!.onerror = ((web.Event event) {
        String detail;
        if (event.isA<web.ErrorEvent>()) {
          final err = event as web.ErrorEvent;
          detail = '${err.message} (${err.filename}:${err.lineno})';
        } else {
          detail = 'unknown error';
        }
        onError?.call(
          StateError(
            'hand_tracker_worker.js failed to load or threw an uncaught error. $detail',
          ),
          StackTrace.current,
        );
      }).toJS;

      _worker!.postMessage(
        {'type': 'init', 'wasmPath': _kWasmPath, 'modelPath': _kModelPath}
            .jsify()!,
      );
      // The rAF capture loop starts when the worker posts 'ready'.
    } catch (e, st) {
      _initialized = false;
      _worker?.terminate();
      _worker = null;
      _video?.remove();
      _video = null;
      final categorized = _categorizeCameraError(e);
      if (!_cameraReady.isCompleted) _cameraReady.completeError(categorized, st);
      onError?.call(categorized, st);
    }
  }

  /// Maps a raw worker error string to a user-readable message.
  ///
  /// The worker sends `String(e)` which includes the JS error class name and
  /// message, e.g. "TypeError: Failed to fetch https://...".
  static String _categorizeWorkerError(String rawMsg) {
    // Network failure loading WASM runtime or .task model from CDN.
    if (rawMsg.contains('Failed to fetch') || rawMsg.contains('NetworkError')) {
      return 'MediaPipe model failed to load — check your internet connection '
          'or CDN reachability, then reload.';
    }
    // Content-Security-Policy blocking the WASM/ES module bundle.
    if (rawMsg.contains('Content-Security-Policy') ||
        rawMsg.contains("'unsafe-eval'")) {
      return 'MediaPipe blocked by Content-Security-Policy — add '
          "'script-src cdn.jsdelivr.net' and 'wasm-unsafe-eval' to your CSP.";
    }
    // CORS rejection when serving the worker script from a different origin.
    if (rawMsg.contains('CORS') || rawMsg.contains('cross-origin')) {
      return 'hand_tracker_worker.js blocked by CORS — serve it from the same '
          'origin as index.html.';
    }
    return 'MediaPipe initialization failed: $rawMsg';
  }

  /// Maps a raw JS exception from getUserMedia into a user-readable [StateError].
  static StateError _categorizeCameraError(Object e) {
    try {
      // On web, getUserMedia rejections arrive as JS DOMExceptions.
      // Avoid `is JSObject` (invalid_runtime_check_with_js_interop_types);
      // cast to JSObject first, then use the dart:js_interop isA<T>() API.
      final jsObj = e as JSObject;
      if (jsObj.isA<web.DOMException>()) {
        final dom = jsObj as web.DOMException;
        final message = switch (dom.name) {
          'NotAllowedError' || 'PermissionDeniedError' =>
              'Camera permission denied — allow camera access in browser settings '
                  'and reload the page.',
          'NotFoundError' || 'DevicesNotFoundError' =>
              'No camera found — connect a camera and reload.',
          'NotReadableError' || 'TrackStartError' =>
              'Camera is in use by another application — close it and try again.',
          'OverconstrainedError' || 'ConstraintNotSatisfiedError' =>
              'Camera constraints could not be satisfied.',
          'SecurityError' =>
              'Camera blocked — serve the page over HTTPS or localhost.',
          _ => 'Camera error (${dom.name}): ${dom.message}',
        };
        return StateError(message);
      }
    } catch (_) {}
    // TypeError when navigator.mediaDevices is undefined (very old browser or
    // non-secure context not caught by the isSecureContext guard above).
    return StateError(
      'Camera not available — serve the page over HTTPS or localhost.',
    );
  }

  void _onWorkerMessage(web.MessageEvent event) {
    if (_disposed) return;
    final raw = event.data.dartify();
    if (raw is! Map) return;
    final type = raw['type'] as String?;

    switch (type) {
      case 'ready':
        // Worker finished loading MediaPipe — start capturing frames.
        web.window.requestAnimationFrame(_captureLoopJS);

      case 'landmarks':
        _workerBusy = false;
        final tsMs = (raw['timestampMs'] as num).toDouble();
        final workerLatencyMs = (raw['workerLatencyMs'] as num? ?? 0).toDouble();
        final roundTripMs = DateTime.now().millisecondsSinceEpoch - _lastSendMs;
        final hands = raw['hands'] as List?;

        // Latency instrument: log every 60 frames (~2 s at 30 fps).
        _frameCount++;
        if (_frameCount % 60 == 0) {
          debugPrint(
            '[air_pointer] frame=$_frameCount '
            'worker=${workerLatencyMs.toStringAsFixed(1)} ms '
            'round-trip=$roundTripMs ms',
          );
        }

        final dt = _prevTimestampMs > 0
            ? (tsMs - _prevTimestampMs) / 1000.0
            : 1.0 / 30.0;
        _prevTimestampMs = tsMs;

        // Convert JS-dartified hand arrays to HandLandmarkPoint lists.
        final handednesses = raw['handednesses'] as List?;
        List<HandLandmarkPoint>? lms;
        List<HandLandmarkPoint>? secondLms;
        if (hands != null) {
          List<HandLandmarkPoint> parseHand(List<Object?> raw) =>
              raw.map((pt) {
                final m = pt as Map<Object?, Object?>;
                return HandLandmarkPoint(
                  (m['x'] as num).toDouble(),
                  (m['y'] as num).toDouble(),
                  (m['z'] as num).toDouble(),
                  visibility: (m['visibility'] as num?)?.toDouble() ?? 1.0,
                );
              }).toList();
          if (hands.isNotEmpty) lms = parseHand(hands[0] as List<Object?>);
          if (hands.length >= 2) {
            secondLms = parseHand(hands[1] as List<Object?>);
          }
        }

        final result = _recognizer.process(
          landmarks: lms,
          secondHandLandmarks: secondLms,
          dt: dt,
          canvasSize: _canvasSize,
        );
        for (final e in result.events) {
          _emit(e);
        }
        if (!_debugController.isClosed) {
          _debugController.add(GestureDebugInfo(
            phase: result.debug.phase,
            pinchDistance: result.debug.pinchDistance,
            landmarks: result.debug.landmarks,
            secondHandLandmarks: result.debug.secondHandLandmarks,
            isTwoHandActive: result.debug.isTwoHandActive,
            handedness: _parseHandedness(handednesses, 0),
            secondHandedness: _parseHandedness(handednesses, 1),
            dwellProgress: result.debug.dwellProgress,
            isPointing: result.debug.isPointing,
            workerLatencyMs: workerLatencyMs,
            roundTripMs: roundTripMs,
          ));
        }

      case 'error':
        final rawMsg = raw['message'] as String? ?? 'unknown error';
        debugPrint('[air_pointer] MediaPipe init error: $rawMsg');
        onError?.call(
          StateError(_categorizeWorkerError(rawMsg)),
          StackTrace.current,
        );

      case 'init_error': // reserved for future typed worker errors
        break;
    }
  }

  static Handedness _parseHandedness(List<Object?>? list, int index) {
    if (list == null || index >= list.length) return Handedness.unknown;
    return switch ((list[index] as String?)?.toLowerCase()) {
      'left' => Handedness.left,
      'right' => Handedness.right,
      _ => Handedness.unknown,
    };
  }

  void _captureLoop(JSNumber timestamp) {
    if (_disposed || _video == null || _worker == null) return;

    // Always reschedule first so the loop survives even if we skip this frame.
    web.window.requestAnimationFrame(_captureLoopJS);

    if (_video!.readyState < 2 || _workerBusy) return;

    _workerBusy = true;
    final tsMs = timestamp.toDartDouble;

    // Capture the video frame as an ImageBitmap (GPU blit, effectively free).
    // Ownership is transferred to the worker — no copy is made.
    web.window.createImageBitmap(_video!).toDart.then(
      (bitmap) {
        if (_disposed || _worker == null) {
          bitmap.close();  // we own it and won't send it
          return;
        }
        // Build the message with setProperty so the ImageBitmap (a JSAny) is
        // embedded directly. jsify() is unreliable for non-primitive JSAny values.
        final msg = JSObject();
        msg.setProperty('type'.toJS, 'detect'.toJS);
        msg.setProperty('frame'.toJS, bitmap);
        msg.setProperty('timestampMs'.toJS, tsMs.toJS);

        _lastSendMs = DateTime.now().millisecondsSinceEpoch;
        _worker!.postMessage(msg, [bitmap as JSObject].toJS);
      },
      onError: (_) {
        _workerBusy = false;  // createImageBitmap failed; release lock
      },
    );
  }

  void _setupPreview(web.MediaStream stream) {
    final preview = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..srcObject = stream;
    preview.style
      ..width = '100%'
      ..height = '100%'
      ..transform = 'scaleX(-1)';  // mirror for natural self-view
    preview.style.setProperty('object-fit', 'cover');

    _previewVideo = preview;
    _previewViewType = 'air_pointer_camera_${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      _previewViewType!,
      (_) => _previewVideo!,
    );
    // Camera feed is live — FutureBuilder can show the preview widget.
    _cameraReady.complete();
  }

  /// Returns a widget that shows the live camera feed.
  ///
  /// Shows a dark placeholder while the camera is initialising. Call
  /// [initialize] before (or concurrently with) embedding this widget.
  Widget buildCameraPreview({double? width, double? height}) =>
      FutureBuilder<void>(
        future: _cameraReady.future,
        builder: (context, snapshot) {
          Widget inner;
          if (snapshot.hasError) {
            inner = const ColoredBox(
              color: Color(0xFF2D0000),
              child: Center(
                child: Text(
                  'Camera unavailable.\nCheck console for details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
                ),
              ),
            );
          } else if (snapshot.connectionState == ConnectionState.done) {
            inner = HtmlElementView(viewType: _previewViewType!);
          } else {
            inner = const ColoredBox(
              color: Color(0xFF1C1C1E),
              child: Center(
                child: Text(
                  'Starting camera…',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
              ),
            );
          }
          return SizedBox(width: width, height: height, child: inner);
        },
      );

  void _emit(PointerInputEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => child;

  @override
  void dispose() {
    _disposed = true;
    _recognizer.reset();
    // Ask the worker to close itself gracefully, then hard-terminate.
    _worker?.postMessage({'type': 'dispose'}.jsify()!);
    _worker?.terminate();
    _worker = null;
    _previewVideo?.srcObject = null;
    _previewVideo = null;
    final video = _video;
    if (video != null) {
      final src = video.srcObject;
      if (src != null && src.isA<web.MediaStream>()) {
        final s = src as web.MediaStream;
        final tracks = s.getTracks();
        for (var i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      }
      video.srcObject = null;
      video.remove();
      _video = null;
    }
    unawaited(_debugController.close());
    unawaited(_controller.close());
  }
}
