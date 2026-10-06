import '../terminal/screen_buffer.dart';

/// Kinds of BBS screen the app can tell apart. Only [unknown] exists for now;
/// native views for specific screens will add values here.
enum ScreenKind { unknown }

abstract class ScreenRecognizer {
  ScreenKind recognize(ScreenBuffer screen);
}

class NullScreenRecognizer implements ScreenRecognizer {
  @override
  ScreenKind recognize(ScreenBuffer screen) => ScreenKind.unknown;
}
