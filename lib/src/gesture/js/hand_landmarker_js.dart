import 'dart:js_interop';

import 'package:air_pointer/src/gesture/js/normalized_landmark_js.dart';

@JS('HandLandmarker')
extension type HandLandmarker._(JSObject _) implements JSObject {
  external static JSPromise<HandLandmarker> createFromOptions(
    JSAny vision,
    JSObject options,
  );

  external HandLandmarkerResult detectForVideo(
    JSObject videoElement,
    int timestamp,
  );

  external void close();
}

extension type HandLandmarkerResult._(JSObject _) implements JSObject {
  external JSArray<JSArray<NormalizedLandmark>> get landmarks;
}
