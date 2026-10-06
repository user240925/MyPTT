import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/core does not depend on Flutter', () {
    final offenders = Directory('lib/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final src = f.readAsStringSync();
      return src.contains("'package:flutter") || src.contains("'dart:ui'");
    }).map((f) => f.path);
    expect(offenders, isEmpty);
  });
}
