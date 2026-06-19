import 'package:flutter/painting.dart';

final class DraggableBox {
  const DraggableBox({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  DraggableBox shifted(Offset delta) =>
      DraggableBox(rect: rect.shift(delta), color: color);

  bool contains(Offset point) => rect.contains(point);
}
