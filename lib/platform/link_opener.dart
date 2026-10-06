import 'package:url_launcher/url_launcher.dart';

/// Parses [url] if it is safe to hand to the system browser: only absolute
/// http and https URLs with a host. Text on a BBS screen is untrusted.
Uri? externalUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Opens [url] in the system browser. Returns false if it was rejected or
/// could not be opened.
Future<bool> openExternalUrl(String url) async {
  final uri = externalUri(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
