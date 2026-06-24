# air_pointer — Claude Code guide

## Architecture invariant (never break this)

`NormalizedLandmark`, `HandLandmarker`, `JSObject`, and any `dart:js_interop`
type must not appear outside `lib/src/gesture/`. `PointerInputEvent` (and its
subclasses) is the only type that may cross the boundary. This is checked by
design: nothing in `lib/src/controller/`, `lib/src/mouse/`, or `lib/src/filter/`
imports `dart:js_interop`.

## Quality gate

Always run from the package root (not from `example/`):

```
flutter analyze   # static analysis + dart_code_linter
flutter test      # unit tests
```

The `dart_code_linter` dev dependency is wired into `analysis_options.yaml` and
runs automatically with `flutter analyze` — no separate invocation needed.

Lint exclusions for files that legitimately exceed the per-file metrics are in
`analysis_options.yaml` under `dart_code_linter.metrics-exclude`. Add new
exclusions sparingly and explain why in the PR.

## Testing philosophy

`HandGestureRecognizer` is a pure-Dart state machine with zero platform
dependencies — test it directly by calling `.process()` with synthetic
`HandLandmarkPoint` lists. No camera, no browser, no Flutter widget tree.
Tests live in `test/gesture/hand_gesture_recognizer_test.dart`.

The same applies to `GestureCalibrator`, `GestureClassifier`, and
`OneEuroFilter` — all are unit-testable in isolation. Any new gesture logic
should have corresponding tests before the PR is opened.

## Platform split

`GestureInputSource` is a conditional export:
- Web: `lib/src/gesture/gesture_input_source_web.dart` (MediaPipe via web worker)
- Native: `lib/src/gesture/gesture_input_source_native.dart` (no-op stub; consumers
  wire their own `LandmarkProvider`)

Changes that affect both platforms must update both files.

## Self-hosting CDN assets

The MediaPipe WASM runtime and `.task` model load from CDN by default. For
offline or CSP-restricted deployments, set `mediaPipeBaseUrl` and `modelAssetUrl`
on `GestureInputSource`. The bundle is expected at `<base>/vision_bundle.mjs`
and WASM files at `<base>/wasm/`.

## Key constants

| Constant | Value | Location |
|----------|-------|----------|
| MediaPipe version pin | `0.10.21` | `_kMediaPipeVersion` in `gesture_input_source_web.dart` |
| Default pinch close | `0.05` | `HandGestureRecognizer` |
| Default pinch open | `0.08` | `HandGestureRecognizer` |
| Default acquire frames | `3` | `HandGestureRecognizer` |
| Default grace frames | `5` | `HandGestureRecognizer` |

When bumping the MediaPipe pin, verify the worker message protocol has not
changed (the `detect` / `landmarks` / `error` / `ready` message types).

## Changing public API

Sealed classes (`PointerInputEvent` and its subclasses) are used with exhaustive
`switch` by consumers. Adding a new subclass is a breaking change — existing
switches will fail to compile. Discuss in an issue before adding event types.

`HandTrackingStatus` follows the same rule.

`CanvasInputSource` is an `interface` — adding required methods is breaking.
Adding optional methods with a default implementation is safe.

## CHANGELOG discipline

- Every user-visible change goes in `CHANGELOG.md` under the appropriate version.
- Bug fixes go under `### Bug fixes`, new features under `### New` (or the
  relevant component heading).
- Internal refactors with no behaviour change do not need a CHANGELOG entry.
