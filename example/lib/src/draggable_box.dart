import 'package:flutter/painting.dart';

final class DraggableBox {
  const DraggableBox({required this.rect, required this.color, this.label});

  final Rect rect;
  final Color color;
  final String? label;

  DraggableBox shifted(Offset delta) =>
      DraggableBox(rect: rect.shift(delta), color: color, label: label);

  bool contains(Offset point) => rect.contains(point);
}
