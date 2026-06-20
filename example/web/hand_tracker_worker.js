// Module web worker — runs MediaPipe HandLandmarker off the main thread so
// inference never blocks Flutter's UI rendering.
//
// Protocol (all messages are plain JSON-serialisable objects):
//   main → worker  { type: 'init',    wasmPath: string, modelPath: string }
//   main → worker  { type: 'detect',  frame: ImageBitmap, timestampMs: number }
//   main → worker  { type: 'dispose' }
//
//   worker → main  { type: 'ready' }
//   worker → main  { type: 'landmarks',
//                    hands: Array<Array<{x,y,z,visibility}>>,
//                    handednesses: Array<'Left'|'Right'|'Unknown'>,
//                    timestampMs: number, workerLatencyMs: number }
//   worker → main  { type: 'error', message: string }
//
// The worker always replies to every 'detect' message (with an empty hands
// array on detection failure) so the main thread's _workerBusy flag is
// always released.

import { FilesetResolver, HandLandmarker }
  from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision_bundle.mjs';

let landmarker = null;

self.onmessage = async (event) => {
  const { type } = event.data;

  // ── init ──────────────────────────────────────────────────────────────────
  if (type === 'init') {
    try {
      const vision = await FilesetResolver.forVisionTasks(event.data.wasmPath);
      landmarker = await HandLandmarker.createFromOptions(vision, {
        baseOptions: {
          modelAssetPath: event.data.modelPath,
          delegate: 'CPU',  // GPU conflicts with Flutter's WebGL context
        },
        runningMode: 'VIDEO',
        numHands: 2,
      });
      self.postMessage({ type: 'ready' });
    } catch (e) {
      self.postMessage({ type: 'error', message: String(e) });
    }
    return;
  }

  // ── detect ────────────────────────────────────────────────────────────────
  if (type === 'detect') {
    const frame = event.data.frame;
    const timestampMs = event.data.timestampMs;
    const recvMs = Date.now();

    if (!landmarker) {
      frame?.close();
      // Always reply so the main thread's _workerBusy is cleared.
      self.postMessage({ type: 'landmarks', hands: [], handednesses: [], timestampMs, workerLatencyMs: 0 });
      return;
    }

    let hands = [];
    let handednesses = [];
    try {
      const result = landmarker.detectForVideo(frame, timestampMs);
      frame.close();  // free GPU memory immediately after detection
      hands = result.landmarks.map(hand =>
        hand.map(({ x, y, z, visibility }) => ({ x, y, z, visibility }))
      );
      // handednesses is an array-of-arrays; take the top category per hand.
      handednesses = (result.handednesses ?? []).map(
        cats => cats[0]?.categoryName ?? 'Unknown'
      );
    } catch (_) {
      frame?.close();
      // Non-fatal — skipped frame. Reply with empty hands so lock is released.
    }

    self.postMessage({
      type: 'landmarks',
      hands,
      handednesses,
      timestampMs,
      workerLatencyMs: Date.now() - recvMs,
    });
    return;
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  if (type === 'dispose') {
    landmarker?.close();
    landmarker = null;
    self.close();
  }
};
