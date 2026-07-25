import 'dart:io';

import 'package:body_frame/core/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('예외 메시지와 파일 경로를 로그에 남기지 않는다', () {
    final entries = <Map<String, dynamic>>[];
    final logger = AppLogger.instance;
    logger.sink = entries.add;
    addTearDown(() => logger.sink = null);

    logger.error(
      'photo.failure',
      err: const FileSystemException(
        '회원 사진을 읽지 못함',
        '/private/sensitive/member/photo.jpg',
      ),
    );

    expect(entries, hasLength(1));
    final encoded = entries.single.toString();
    expect(entries.single['errorType'], 'FileSystemException');
    expect(encoded, isNot(contains('sensitive')));
    expect(encoded, isNot(contains('회원 사진')));
  });
}
