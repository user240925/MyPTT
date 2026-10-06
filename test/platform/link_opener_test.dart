import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/platform/link_opener.dart';

void main() {
  test('accepts http and https URLs', () {
    expect(externalUri('https://www.ptt.cc/bbs/Stock/index.html')?.host, 'www.ptt.cc');
    expect(externalUri('http://example.com/a?b=c')?.scheme, 'http');
  });

  test('rejects other schemes and malformed input', () {
    expect(externalUri('javascript:alert(1)'), isNull);
    expect(externalUri('file:///etc/passwd'), isNull);
    expect(externalUri('tel:110'), isNull);
    expect(externalUri('myapp://open'), isNull);
    expect(externalUri('https://'), isNull);
    expect(externalUri('not a url'), isNull);
    expect(externalUri(''), isNull);
  });
}
