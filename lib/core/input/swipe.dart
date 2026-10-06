import '../terminal/term_keys.dart';

enum Swipe { left, right, up, down }

/// How much longer the main axis must be than the other for a drag to count
/// as a swipe, so a diagonal drag is not misread.
const double _dominance = 1.5;

/// Classifies a finished one-finger drag by its total displacement, or
/// returns null if it is too short or too diagonal.
Swipe? classifySwipe(double dx, double dy, {double minDistance = 48}) {
  if (!dx.isFinite || !dy.isFinite) return null;
  final ax = dx.abs(), ay = dy.abs();
  if (ax < minDistance && ay < minDistance) return null;
  if (ax >= ay * _dominance) return dx > 0 ? Swipe.right : Swipe.left;
  if (ay >= ax * _dominance) return dy > 0 ? Swipe.down : Swipe.up;
  return null;
}

/// Swiping right goes back, left enters, up and down page through content.
TermKey keyForSwipe(Swipe swipe) => switch (swipe) {
      Swipe.right => TermKey.left,
      Swipe.left => TermKey.right,
      Swipe.up => TermKey.pageDown,
      Swipe.down => TermKey.pageUp,
    };
