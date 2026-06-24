Contributing to air_pointer

Thank you for your interest in contributing to air_pointer! 🚀

air_pointer provides a platform-agnostic input abstraction for Flutter canvases. The goal is to allow applications to consume a single stream of pointer events regardless of whether input originates from a mouse, touch screen, trackpad, or camera-based hand tracking.

Before contributing, please read this guide carefully.

⸻

Core Design Principles

The project is built around three principles:

1. Source Independence

Canvas consumers should never need to know where input originated.

Whether events come from:

* Mouse
* Trackpad
* Touch
* Hand gestures
* Future input sources

all interactions must be represented as PointerInputEvents.

2. Stable Public API

Public APIs should remain simple and predictable.

Breaking changes require:

* Discussion in an issue
* Documentation updates
* Migration guidance

3. Strict Architecture Boundaries

The following types must never leak outside the gesture implementation layer:

* NormalizedLandmark
* HandLandmarker
* JSObject
* dart:js_interop types
* MediaPipe-specific classes

Only PointerInputEvent types may cross package boundaries.

⸻

Development Prerequisites

| Requirement | Minimum |
|---|---|
| Dart SDK | 3.9.2 |
| Flutter SDK | 3.44.0 |
| Browser (for Web) | Chrome ≥ 88, Firefox ≥ 89, Safari ≥ 15 |

`dart_code_linter` is a dev dependency and is automatically invoked when you run
`flutter analyze` — no separate installation step is needed.

⸻

Development Setup

Clone the repository:

git clone git@github.com:Ranveer-Singh-Gour/air_pointer.git
cd air_pointer

Install dependencies:

flutter pub get

Run static analysis:

flutter analyze

Run tests:

flutter test

Run the example application:

cd example
flutter run -d chrome

⸻

Project Structure

lib/
├── air_pointer.dart
└── src/
    ├── controller/
    ├── events/
    ├── mouse/
    ├── gesture/
    └── filter/

Responsibilities

Module	Responsibility
controller	Input orchestration
events	Shared event model
mouse	Mouse/trackpad/touch support
gesture	MediaPipe integration + calibration
filter	Signal smoothing (OneEuroFilter)

⸻

Adding a New Input Source

New input sources are welcome.

Examples:

* Eye tracking
* Stylus input
* AR/VR controllers
* Accessibility devices

Requirements:

1. Implement the input source contract.
2. Emit only PointerInputEvents.
3. Avoid leaking platform-specific types.
4. Support proper lifecycle cleanup.
5. Add tests and documentation.

The canvas layer must remain unaware of the source implementation.

⸻

Coding Guidelines

General

* Follow SOLID principles.
* Prefer composition over inheritance.
* Keep APIs minimal.
* Avoid unnecessary dependencies.
* Write self-documenting code.

Naming

Use clear and descriptive names.

Good:

CanvasScaleEvent
GestureCalibrationResult
PointerInputEvent

Avoid:

Event2
DataModel
HelperUtil

Error Handling

Do not silently swallow exceptions.

Use meaningful error messages and expose failures through public callbacks where appropriate.

⸻

Testing Requirements

All new functionality should include tests whenever possible.

Focus on:

Event Translation

Verify platform-specific inputs are converted correctly.

Examples:

* Pinch → CanvasDownEvent
* Drag → CanvasMoveEvent
* Release → CanvasUpEvent

State Transitions

Verify:

* Hover → Down
* Down → Move
* Move → Up
* Move → Cancel

Calibration

Verify threshold calculations remain stable across edge cases.

Filtering

Verify smoothing logic behaves consistently for noisy input streams.

⸻

Gesture Module Guidelines

The gesture implementation is the most sensitive part of the project.

When working inside lib/src/gesture/:

* Minimize JavaScript interop exposure.
* Keep MediaPipe-specific code isolated.
* Avoid introducing dependencies into shared modules.
* Maintain compatibility with Flutter Web.

Any architecture change affecting gesture processing should be discussed before implementation.

⸻

Performance Expectations

air_pointer targets real-time interaction.

Contributions should:

* Avoid excessive allocations.
* Avoid blocking the UI thread.
* Minimize per-frame work.
* Maintain smooth cursor movement.

Performance regressions may block a pull request.

⸻

Documentation

If your change affects:

* Public APIs
* Event behavior
* Gesture recognition
* Calibration flow
* Setup instructions

please update:

* README.md
* Example application
* API documentation

Documentation changes are considered part of the feature.

⸻

Pull Requests

Before opening a pull request:

* Code builds successfully
* flutter analyze passes
* Tests pass
* Documentation updated
* Example app verified
* No architecture boundary violations

Pull Request Template

## Summary
Describe the change.
## Motivation
Why is this change needed?
## Testing
How was this tested?
## Breaking Changes
List any breaking changes.
## Screenshots / Videos
(Optional)

⸻

Reporting Bugs

Please include:

* Flutter version
* Browser (for Web issues)
* Operating system
* Reproduction steps
* Expected behavior
* Actual behavior
* Logs or screenshots

⸻

Security Issues

Please do not publicly disclose security vulnerabilities.

Open a private security report with:

* Description
* Impact
* Reproduction steps
* Suggested mitigation

⸻

Future Contributions

Areas where contributions are especially welcome:

* Additional input sources
* Better calibration workflows
* Performance improvements
* Accessibility features
* Native platform gesture support
* Improved debugging and diagnostics

Thank you for helping make air_pointer more accessible, flexible, and platform-independent.
