import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN/비밀번호 해시 유틸리티. MVP.md 11장: 원문은 저장하지 않고 salt+해시만
/// 보관한다.
///
/// flutter_secure_storage 등 플랫폼 플러그인에 의존하지 않는 순수 함수라서
/// 플러그인 없이도 단위 테스트할 수 있다.
class PinHasher {
  PinHasher._();

  /// 무작위 salt(16바이트, URL-safe base64)를 생성한다.
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// salt와 PIN을 결합한 SHA-256 해시(hex)를 계산한다.
  static String hash(String secret, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$secret'));
    return digest.toString();
  }

  /// 저장용 레코드 문자열(`salt:hash`)을 생성한다.
  static String createRecord(String secret) {
    final salt = generateSalt();
    return '$salt:${hash(secret, salt)}';
  }

  /// 저장된 [record](`salt:hash`)와 입력 [secret]이 일치하는지 검증한다.
  static bool verify(String secret, String record) {
    final parts = record.split(':');
    if (parts.length != 2) return false;
    return hash(secret, parts[0]) == parts[1];
  }
}
