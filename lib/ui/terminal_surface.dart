import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/connection/connection.dart';
import '../core/input/swipe.dart';
import '../core/session.dart';
import '../core/terminal/selection.dart';
import '../core/terminal/term_keys.dart';
import 'terminal_painter.dart';

/// Draws the terminal and turns touch gestures into keys, zoom, selection,
/// and link taps.
class TerminalSurface extends StatefulWidget {
  const TerminalSurface({
    super.key,
    required this.session,
    this.inputEnabled = true,
    this.onTapBackground,
    this.onOpenUrl,
    this.onCopied,
  });

  final TerminalSession session;

  /// When false, swipes do not send keys.
  final bool inputEnabled;
  final VoidCallback? onTapBackground;
  final ValueChanged<String>? onOpenUrl;
  final ValueChanged<String>? onCopied;

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  static const Duration _blinkInterval = Duration(milliseconds: 600);

  /// 80 columns of 1:2 cells by 24 rows.
  static const double _aspectRatio = 80 / (24 * 2);
  static const double _maxScale = 4;

  /// Below this the view snaps back to exactly 1x.
  static const double _snapScale = 1.05;

  late final StreamSubscription<void> _updates;
  late final Timer _blink;
  bool _blinkOn = true;

  /// Size and top-left corner of the unzoomed terminal within this widget.
  Size _size = Size.zero;
  Offset _origin = Offset.zero;

  double _scale = 1;
  Offset _offset = Offset.zero;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  // Swipes are measured from raw pointer positions, touch-down to lift-off,
  // because the scale recognizer only reports movement after its slop.
  int _pointers = 0;
  int? _firstPointer;
  Offset _downPosition = Offset.zero;
  Offset _lastPosition = Offset.zero;
  double _scaleAtDown = 1;

  /// True from the moment a second finger touches until every finger lifts.
  bool _hadMultiTouch = false;

  /// True while a long-press selection is in progress.
  bool _selecting = false;

  /// True while a mouse pointer is over a link.
  bool _hoveringUrl = false;
  Selection? _selection;

  @override
  void initState() {
    super.initState();
    _updates = widget.session.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _blink = Timer.periodic(_blinkInterval, (_) {
      if (mounted) setState(() => _blinkOn = !_blinkOn);
    });
  }

  @override
  void dispose() {
    _blink.cancel();
    _updates.cancel();
    super.dispose();
  }

  Offset _clampOffset(Offset o, double scale) {
    final minX = _size.width * (1 - scale), minY = _size.height * (1 - scale);
    return Offset(
      o.dx.clamp(minX, 0.0).toDouble(),
      o.dy.clamp(minY, 0.0).toDouble(),
    );
  }

  CellPos _cellAt(Offset local) {
    final screen = widget.session.screen;
    final cw = _size.width / screen.cols, ch = _size.height / screen.rows;
    if (cw <= 0 || ch <= 0) return const CellPos(0, 0);
    final p = (local - _origin - _offset) / _scale;
    int cell(double v, int count) {
      if (!v.isFinite) return 0;
      final i = v.floor();
      return i < 0 ? 0 : (i >= count ? count - 1 : i);
    }

    return CellPos(cell(p.dy / ch, screen.rows), cell(p.dx / cw, screen.cols));
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _firstPointer = e.pointer;
      _downPosition = _lastPosition = e.localPosition;
      _scaleAtDown = _scale;
      _hadMultiTouch = false;
      _selecting = false;
    } else {
      _hadMultiTouch = true;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer == _firstPointer) _lastPosition = e.localPosition;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer == _firstPointer) _lastPosition = e.localPosition;
    if (_pointers > 0) _pointers--;
    if (_pointers > 0) return;
    final plainDrag = !_hadMultiTouch && !_selecting && _scaleAtDown == 1;
    if (!plainDrag || !widget.inputEnabled) return;
    final drag = _lastPosition - _downPosition;
    final swipe = classifySwipe(drag.dx, drag.dy);
    if (swipe != null) {
      widget.session.sendBytes(bytesForKey(keyForSwipe(swipe)));
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_pointers > 0) _pointers--;
    // A cancelled touch must never end up as a swipe.
    _hadMultiTouch = true;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      final scale = (_startScale * d.scale).clamp(1.0, _maxScale).toDouble();
      // Keep the point under the fingers fixed while zooming.
      final anchor = (_startFocal - _origin - _startOffset) / _startScale;
      final offset = d.localFocalPoint - _origin - anchor * scale;
      setState(() {
        _scale = scale;
        _offset = _clampOffset(offset, scale);
      });
    } else if (_scale > 1) {
      setState(() {
        _offset = _clampOffset(
          _startOffset + (d.localFocalPoint - _startFocal),
          _scale,
        );
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return;
    if (_scale < _snapScale && (_scale != 1 || _offset != Offset.zero)) {
      setState(() {
        _scale = 1;
        _offset = Offset.zero;
      });
    }
  }

  String? _urlAtPosition(Offset local) {
    // In portrait most of the widget is empty space below the terminal;
    // a position there must not land on the nearest edge cell.
    if (!(_origin & _size).contains(local)) return null;
    final session = widget.session;
    return urlAt(session.screen, session.codec, _cellAt(local));
  }

  void _setHoveringUrl(bool value) {
    if (value != _hoveringUrl) setState(() => _hoveringUrl = value);
  }

  void _onTapUp(TapUpDetails d) {
    if (_selection != null) {
      setState(() => _selection = null);
      return;
    }
    final url = _urlAtPosition(d.localPosition);
    if (url != null) {
      widget.onOpenUrl?.call(url);
    } else {
      widget.onTapBackground?.call();
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _selecting = true;
    final cell = _cellAt(d.localPosition);
    setState(() => _selection = Selection(cell, cell));
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final anchor = _selection?.anchor;
    if (anchor == null) return;
    setState(() => _selection = Selection(anchor, _cellAt(d.localPosition)));
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final selection = _selection;
    if (selection == null) return;
    final session = widget.session;
    final text = textInRange(session.screen, session.codec, selection);
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    widget.onCopied?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        var w = constraints.maxWidth, h = w / _aspectRatio;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * _aspectRatio;
        }
        _size = Size(w, h);
        _origin = Offset((constraints.maxWidth - w) / 2, 0);
        _offset = _clampOffset(_offset, _scale);

        return MouseRegion(
          cursor: _hoveringUrl
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (e) =>
              _setHoveringUrl(_urlAtPosition(e.localPosition) != null),
          onExit: (_) => _setHoveringUrl(false),
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              onLongPressStart: _onLongPressStart,
              onLongPressMoveUpdate: _onLongPressMove,
              onLongPressEnd: _onLongPressEnd,
              child: ColoredBox(
                color: Colors.black,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: ClipRect(
                      child: Transform.translate(
                        offset: _offset,
                        child: Transform.scale(
                          key: const Key('terminal-zoom'),
                          scale: _scale,
                          alignment: Alignment.topLeft,
                          child: CustomPaint(
                            size: _size,
                            painter: TerminalPainter(
                              screen: session.screen,
                              codec: session.codec,
                              blinkOn: _blinkOn,
                              showCursor:
                                  session.status == ConnectionStatus.connected,
                              selection: _selection,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
