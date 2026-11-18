import 'dart:io';

import 'package:bodymark/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('앱 버전 상수는 pubspec.yaml의 version과 같다', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    final value = line.substring('version:'.length).trim();
    expect(value, '${AppInfo.version}+${AppInfo.buildNumber}');
  });
}
