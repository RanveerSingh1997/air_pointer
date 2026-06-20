// Classic web worker — MediaPipe HandLandmarker runs off the main thread.
//
// This file must stay a CLASSIC worker (no type:'module' on the Worker
// constructor). MediaPipe's Emscripten WASM runtime calls importScripts()
// internally; that API is only available in classic workers, not module workers.
// MediaPipe is loaded via dynamic import() instead, which is supported in
// classic workers since Chrome 80.
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

let landmarker = null;
let initialized = false;

self.onmessage = async (event) => {
  const { type } = event.data;

  // ── init ──────────────────────────────────────────────────────────────────
  if (type === 'init') {
    if (initialized) return;  // idempotent — ignore duplicate init messages
    initialized = true;
    try {
      // Dynamic import() keeps the ESM bundle while allowing importScripts()
      // to remain available for MediaPipe's WASM sub-worker threads.
      const { FilesetResolver, HandLandmarker } = await import(
        'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision_bundle.mjs'
      );
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
