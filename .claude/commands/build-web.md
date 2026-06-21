Compile the air_pointer example app for Flutter Web. This catches web-specific issues — JS interop errors, conditional import failures, dart2js tree-shaking problems — that `flutter analyze` does not surface.

Run from the example subdirectory using an absolute path so the working directory cannot drift:
```
cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer/example && flutter build web --no-pub
```

**Pass criterion**: build exits 0 and prints "✓ Built build/web".

**On failure**: show the full compiler error. Common causes to look for:
- `dart:js_interop` types leaking outside `lib/src/gesture/js/` (architecture boundary violation)
- Missing or broken conditional imports (`gesture_input_source.dart` routing web vs. native)
- A new dependency that lacks a web-compatible implementation
- `hand_tracker_worker.js` referenced from Dart code that no longer matches the actual filename

After reporting the result, return to the package root:
```
cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer
```
