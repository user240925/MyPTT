import 'dart:ui';

const int _up = 1, _down = 2, _left = 4, _right = 8;

/// Box-drawing characters mapped to the arms they extend from the centre.
const Map<int, int> _boxArms = {
  0x2500: _left | _right, // ─
  0x2502: _up | _down, // │
  0x250C: _down | _right, // ┌
  0x2510: _down | _left, // ┐
  0x2514: _up | _right, // └
  0x2518: _up | _left, // ┘
  0x251C: _up | _down | _right, // ├
  0x2524: _up | _down | _left, // ┤
  0x252C: _down | _left | _right, // ┬
  0x2534: _up | _left | _right, // ┴
  0x253C: _up | _down | _left | _right, // ┼
};

/// Draws block, triangle, and box-drawing characters as geometry so adjacent
/// cells join without gaps. Returns false if [codePoint] is not one of them.
bool drawShape(Canvas canvas, Rect box, int codePoint, Color color) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = false;

  // Lower one-eighth block through full block.
  if (codePoint >= 0x2581 && codePoint <= 0x2588) {
    final h = box.height * (codePoint - 0x2580) / 8;
    canvas.drawRect(
      Rect.fromLTRB(box.left, box.bottom - h, box.right, box.bottom),
      paint,
    );
    return true;
  }
  // Left seven-eighths block down to left one-eighth block.
  if (codePoint >= 0x2589 && codePoint <= 0x258F) {
    final w = box.width * (0x2590 - codePoint) / 8;
    canvas.drawRect(
      Rect.fromLTRB(box.left, box.top, box.left + w, box.bottom),
      paint,
    );
    return true;
  }
  // Corner triangles ◢ ◣ ◤ ◥.
  if (codePoint >= 0x25E2 && codePoint <= 0x25E5) {
    final tl = box.topLeft, tr = box.topRight;
    final bl = box.bottomLeft, br = box.bottomRight;
    final points = switch (codePoint) {
      0x25E2 => [bl, br, tr],
      0x25E3 => [tl, bl, br],
      0x25E4 => [tl, tr, bl],
      _ => [tl, tr, br],
    };
    canvas.drawPath(Path()..addPolygon(points, true), paint);
    return true;
  }

  final arms = _boxArms[codePoint];
  if (arms == null) return false;
  final t = box.height / 14 < 1 ? 1.0 : box.height / 14;
  final cx = box.center.dx, cy = box.center.dy, h = t / 2;
  if (arms & _up != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, box.top, cx + h, cy + h), paint);
  }
  if (arms & _down != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, cy - h, cx + h, box.bottom), paint);
  }
  if (arms & _left != 0) {
    canvas.drawRect(Rect.fromLTRB(box.left, cy - h, cx + h, cy + h), paint);
  }
  if (arms & _right != 0) {
    canvas.drawRect(Rect.fromLTRB(cx - h, cy - h, box.right, cy + h), paint);
  }
  return true;
}
