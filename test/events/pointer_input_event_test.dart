import 'package:air_pointer/air_pointer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PointerInputEvent sealed exhaustiveness', () {
    PointerInputEvent makeDown() =>
        const CanvasDownEvent(position: Offset(1, 2));

    test('switch on all subtypes compiles and dispatches', () {
      final event = makeDown();
      final result = switch (event) {
        CanvasTapEvent() => 'tap',
        CanvasDoubleTapEvent() => 'doubleTap',
        CanvasLongPressEvent() => 'longPress',
        CanvasDownEvent() => 'down',
        CanvasMoveEvent() => 'move',
        CanvasUpEvent() => 'up',
        CanvasHoverEvent() => 'hover',
        CanvasScrollEvent() => 'scroll',
        CanvasScaleEvent() => 'scale',
        CanvasScaleEndEvent() => 'scaleEnd',
        CanvasCancelEvent() => 'cancel',
        CanvasSwipeEvent() => 'swipe',
        CanvasGestureEvent() => 'gesture',
      };
      expect(result, 'down');
    });

    test('CanvasDownEvent carries position', () {
      const e = CanvasDownEvent(position: Offset(10, 20));
      expect(e.position, const Offset(10, 20));
    });

    test('CanvasScaleEvent carries all fields', () {
      const e = CanvasScaleEvent(
        focalPoint: Offset(5, 5),
        scaleDelta: 1.05,
        panDelta: Offset(2, 3),
      );
      expect(e.scaleDelta, 1.05);
      expect(e.panDelta, const Offset(2, 3));
      expect(e.rotation, 0.0);
    });

    test('CanvasScaleEvent accepts explicit rotation', () {
      const e = CanvasScaleEvent(
        focalPoint: Offset(0, 0),
        scaleDelta: 1.0,
        panDelta: Offset.zero,
        rotation: 0.1,
      );
      expect(e.rotation, 0.1);
    });

    test('CanvasScrollEvent carries position and delta', () {
      const e = CanvasScrollEvent(
        position: Offset(0, 0),
        delta: Offset(0, 120),
      );
      expect(e.delta.dy, 120);
    });
  });
}
