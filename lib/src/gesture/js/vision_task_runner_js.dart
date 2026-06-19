import 'dart:js_interop';

@JS('FilesetResolver')
extension type FilesetResolver._(JSObject _) implements JSObject {
  external static JSPromise<JSAny> forVisionTasks(JSString path);
}
