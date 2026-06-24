# Known Limitations

This document covers where `air_pointer` works well, where it degrades, and why.
It follows the spirit of an ML model card — honest about scope rather than
marketing the best-case scenario.

---

## MediaPipe HandLandmarker — model behaviour

**What the model does:**
Google MediaPipe HandLandmarker detects up to N hands and returns 21 3-D
landmarks per hand at roughly 30 fps on a modern laptop CPU (CPU delegate only;
the GPU delegate conflicts with Flutter's WebGL context).

**Where it works well:**
- Adult hands in reasonable indoor lighting
- Skin tones from very light to moderately dark
- Distances of roughly 30–80 cm from a typical laptop webcam
- Plain or mildly textured backgrounds

**Where it degrades:**

| Condition | Effect | Mitigation |
|---|---|---|
| Dim / harsh back-lighting | Landmark jitter, dropped frames, false negatives | Add a desk lamp; avoid windows behind you |
| Very dark skin in low light | Higher false-negative rate (hand not detected) | Improve ambient lighting |
| Very small hands (children) | Landmark positions less stable | Lower `acquireFrames`; run calibration |
| Partial occlusion (hand at edge of frame) | Grace window absorbs brief exits; prolonged exit = cancel | Keep hand centred |
| Fast motion | Blur reduces detection confidence | Slow pinch gestures down deliberately |
| Two or more people in frame | Only the first two detected hands are used | Ensure only the intended user is in frame |
| Low-end hardware / slow CPU | Worker latency rises; gesture events lag | Reduce camera resolution in `getUserMedia` constraints |

---

## Skin tone and inclusivity

MediaPipe Hand Landmarker 2023 (the model pinned in this package) was reported
by Google to have improved cross-skin-tone performance over earlier versions.
We have NOT independently replicated controlled measurements across the full
Fitzpatrick scale. Users experiencing consistently poor detection should:

1. Improve ambient lighting (biggest single factor)
2. Run the in-app calibration to tune thresholds to their hand
3. Open an issue with their lighting setup and skin tone description so we can
   track which conditions need the most attention

---

## Platform scope

`GestureInputSource` compiles to a no-op stub on iOS, Android, macOS, Windows,
and Linux. There is no plan to add native MediaPipe integration in this package.
The `CanvasInputSource` boundary is designed so a third-party package could
provide a native implementation and slot in alongside `MouseInputSource`.

---

## Browser requirements

| Requirement | Why |
|---|---|
| HTTPS or `localhost` | `getUserMedia` is restricted to secure contexts |
| `SharedArrayBuffer` support | Required by MediaPipe WASM threads; needs `COOP`/`COEP` headers if self-hosting |
| ES2020 module support | Worker loaded as `type: "module"`; no IE or legacy Edge support |
| Chrome ≥ 88, Firefox ≥ 89, Safari ≥ 15 | Earliest versions with stable `ImageBitmap` + module workers |

---

## CDN dependency

The WASM runtime (~4 MB) and `.task` model (~20 MB) load from
`cdn.jsdelivr.net` and `storage.googleapis.com` on first page load. This means:

- **No offline support** without self-hosting (see README)
- **First-load latency** of 2–10 seconds on a cold cache
- **CSP constraints** — the CDN origins must be allowlisted

---

## Gesture limitations

- **Rotation only from hand tracking, not mouse** — `CanvasScaleEvent` carries
  a `rotation` field (radians, shortest-path delta) that `GestureInputSource`
  populates during two-hand spread/pinch gestures. `MouseInputSource` always
  emits `rotation: 0.0` — Flutter's `ScaleGestureRecognizer` does not expose a
  rotation delta for two-finger trackpad gestures.
- **No velocity prediction** — the 1€ filter reduces jitter but adds latency.
  A Kalman-based predictor would recover some of that latency but is not
  implemented.
- **No left/right handedness distinction** — both hands are treated
  identically. Which hand is `landmarks[0]` vs `landmarks[1]` is determined
  by MediaPipe's internal ordering, not user preference.
- **`CanvasCancelEvent` carries no position** — mid-drag cancels do not
  include the last cursor position. Consumers should cache the last
  `CanvasMoveEvent` position if they need it for rollback animations.
