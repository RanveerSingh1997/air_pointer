import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/filter/one_euro_filter.dart';
import 'package:air_pointer/src/gesture/js/hand_landmarker_js.dart';
import 'package:air_pointer/src/gesture/js/normalized_landmark_js.dart';
import 'package:air_pointer/src/gesture/js/vision_task_runner_js.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const double _kPinchThreshold = 0.05;
const double _kMinCutoff = 1.0;
const double _kBeta = 0.05;
const double _kDeadzonePx = 3.0;

// Pinned to avoid silent breakage when MediaPipe releases incompatible updates.
const String _kMediaPipeVersion = '0.10.21';
const String _kWasmPath =
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$_kMediaPipeVersion/wasm';
const String _kModelPath =
    'https://storage.googleapis.com/mediapipe-models/'
    'hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({this.onError});

  final void Function(Object, StackTrace)? onError;

  final StreamController<PointerInputEvent> _controller =
      StreamController.broadcast();

  HandLandmarker? _landmarker;
  web.HTMLVideoElement? _video;
  web.HTMLVideoElement? _previewVideo;
  String? _previewViewType;

  // Completes when the camera stream is live and the preview view is registered.
  final Completer<void> _cameraReady = Completer<void>();

  bool _initialized = false;
  bool _disposed = false;
  bool _wasDown = false;
  Size _canvasSize = Size.zero;
  Offset _lastEmittedPosition = Offset.zero;

  final OneEuroFilter _xFilter =
      OneEuroFilter(minCutoff: _kMinCutoff, beta: _kBeta);
  final OneEuroFilter _yFilter =
      OneEuroFilter(minCutoff: _kMinCutoff, beta: _kBeta);
  double _prevTimestampMs = 0;

  void updateCanvasSize(Size size) => _canvasSize = size;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    try {
      final vision =
          await FilesetResolver.forVisionTasks(_kWasmPath.toJS).toDart;
      if (_disposed) return;

      // GPU delegate conflicts with Flutter's WebGL context; CPU is reliable on web.
      final options = {
        'baseOptions': {'modelAssetPath': _kModelPath, 'delegate': 'CPU'},
        'runningMode': 'VIDEO',
        'numHands': 2,
      }.jsify()! as JSObject;

      _landmarker =
          await HandLandmarker.createFromOptions(vision, options).toDart;
      if (_disposed) {
        _landmarker?.close();
        _landmarker = null;
        return;
      }

      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..autoplay = true
        ..muted = true     // required by browsers to allow autoplay without user gesture
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
      await video.play().toDart;  // must await — autoplay alone is not reliable
      if (_disposed) return;

      _setupPreview(stream);
      web.window.requestAnimationFrame(_detectionLoop.toJS);
    } catch (e, st) {
      _initialized = false;
      _landmarker?.close();
      _landmarker = null;
      _video?.remove();
      _video = null;
      if (!_cameraReady.isCompleted) _cameraReady.completeError(e, st);
      onError?.call(e, st);
    }
  }

  void _setupPreview(web.MediaStream stream) {
    // Create a separate video element for the visible preview so the hidden
    // detection video is not disturbed by any style changes.
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

  void _detectionLoop(JSNumber timestamp) {
    // Hard-stop: dispose() was called or landmarker was torn down.
    if (_disposed || _landmarker == null || _video == null) return;

    // readyState < 2 (HAVE_CURRENT_DATA) means the video has no frame yet.
    // detectForVideo would throw, so skip and retry on the next frame.
    if (_video!.readyState < 2) {
      web.window.requestAnimationFrame(_detectionLoop.toJS);
      return;
    }

    try {
      final tsMs = timestamp.toDartDouble;
      final dt =
          _prevTimestampMs > 0 ? (tsMs - _prevTimestampMs) / 1000.0 : 1 / 30.0;
      _prevTimestampMs = tsMs;

      final result = _landmarker!.detectForVideo(_video!, tsMs.toInt());
      final hands = result.landmarks;

      if (hands.length == 0) {
        if (_wasDown) {
          _wasDown = false;
          _emit(CanvasUpEvent(position: _lastEmittedPosition));
        }
      } else {
        _processHand(hands[0], dt);
      }
    } catch (_) {
      // Detection errors are non-fatal; the rAF loop continues.
    }

    web.window.requestAnimationFrame(_detectionLoop.toJS);
  }

  void _processHand(JSArray<NormalizedLandmark> landmarks, double dt) {
    final thumb = landmarks[4];
    final index = landmarks[8];

    final dx = thumb.x - index.x;
    final dy = thumb.y - index.y;
    final pinchDist = math.sqrt(dx * dx + dy * dy);
    final isPinched = pinchDist < _kPinchThreshold;

    final rawX = 1.0 - index.x;
    final rawY = index.y;

    final smoothX = _xFilter.filter(rawX, dt);
    final smoothY = _yFilter.filter(rawY, dt);

    final position = Offset(
      smoothX * _canvasSize.width,
      smoothY * _canvasSize.height,
    );

    if (!_wasDown && isPinched) {
      _wasDown = true;
      _lastEmittedPosition = position;
      _emit(CanvasDownEvent(position: position));
    } else if (_wasDown && !isPinched) {
      _wasDown = false;
      _emit(CanvasUpEvent(position: _lastEmittedPosition));
    } else if (_wasDown) {
      final delta = position - _lastEmittedPosition;
      if (delta.distance >= _kDeadzonePx) {
        _lastEmittedPosition = position;
        _emit(CanvasMoveEvent(position: position));
      }
    } else {
      _emit(CanvasHoverEvent(position: position));
    }
  }

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
    _landmarker?.close();
    _landmarker = null;
    _previewVideo?.srcObject = null;
    _previewVideo = null;
    final video = _video;
    if (video != null) {
      final src = video.srcObject;
      if (src != null && src.isA<web.MediaStream>()) {
        final stream = src as web.MediaStream;
        final tracks = stream.getTracks();
        for (var i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      }
      video.srcObject = null;
      video.remove();
      _video = null;
    }
    unawaited(_controller.close());
  }
}
