import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN/비밀번호 원문은 저장하지 않고 salt+비용 기반 해시만 보관하는 유틸리티.
///
/// flutter_secure_storage 등 플랫폼 플러그인에 의존하지 않는 순수 함수라서
/// 플러그인 없이도 단위 테스트할 수 있다.
class PinHasher {
  PinHasher._();

  static const String algorithm = 'pbkdf2-sha256';
  static const int defaultIterations = 100000;

  /// 무작위 salt(16바이트, URL-safe base64)를 생성한다.
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// PBKDF2-HMAC-SHA256으로 32바이트 파생 키를 계산한다.
  static String hash(
    String secret,
    String salt, {
    int iterations = defaultIterations,
  }) {
    if (iterations <= 0) {
      throw ArgumentError.value(iterations, 'iterations');
    }
    final key = utf8.encode(secret);
    final saltBytes = utf8.encode(salt);
    final hmac = Hmac(sha256, key);
    var u = Uint8List.fromList(hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes);
    final result = Uint8List.fromList(u);
    for (var iteration = 1; iteration < iterations; iteration++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var index = 0; index < result.length; index++) {
        result[index] ^= u[index];
      }
    }
    return base64UrlEncode(result);
  }

  /// 저장용 버전 레코드(`algorithm$iterations$salt$hash`)를 생성한다.
  static String createRecord(String secret) {
    final salt = generateSalt();
    return [algorithm, defaultIterations, salt, hash(secret, salt)].join(r'$');
  }

  /// 저장된 레코드와 입력 [secret]이 일치하는지 상수 시간으로 검증한다.
  ///
  /// v1의 `salt:sha256` 레코드는 기존 사용자 잠금을 해제할 수 있도록 계속
  /// 검증하며, [needsUpgrade]로 새 형식 전환 여부를 확인할 수 있다.
  static bool verify(String secret, String record) {
    try {
      final parts = record.split(r'$');
      if (parts.length == 4 && parts[0] == algorithm) {
        final iterations = int.tryParse(parts[1]);
        if (iterations == null || iterations <= 0) return false;
        return _constantTimeEquals(
          hash(secret, parts[2], iterations: iterations),
          parts[3],
        );
      }

      final legacy = record.split(':');
      if (legacy.length != 2) return false;
      final digest = sha256
          .convert(utf8.encode('${legacy[0]}:$secret'))
          .toString();
      return _constantTimeEquals(digest, legacy[1]);
    } catch (_) {
      return false;
    }
  }

  static bool needsUpgrade(String record) => !record.startsWith('$algorithm\$');

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var difference = leftBytes.length ^ rightBytes.length;
    final length = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < length; index++) {
      final leftValue = index < leftBytes.length ? leftBytes[index] : 0;
      final rightValue = index < rightBytes.length ? rightBytes[index] : 0;
      difference |= leftValue ^ rightValue;
    }
    return difference == 0;
  }
}
