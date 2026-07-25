import 'dart:convert';

import 'package:body_frame/features/settings/services/lock_service.dart';
import 'package:body_frame/features/settings/services/pin_hasher.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('실패 횟수와 잠금 제한은 서비스 재생성 후에도 유지된다', () async {
    const storage = FlutterSecureStorage();
    final service = LockServiceImpl(secureStorage: storage);
    await service.setSecret('1234');

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(await service.verifySecret('0000'), isFalse);
    }
    final state = await service.loadThrottleState();
    expect(state.failedAttempts, 5);
    expect(state.isLockedOut, isTrue);

    final restarted = LockServiceImpl(secureStorage: storage);
    expect((await restarted.loadThrottleState()).isLockedOut, isTrue);
    expect(await restarted.verifySecret('1234'), isFalse);
  });

  test('기존 단일 SHA-256 레코드는 성공 검증 후 PBKDF2 형식으로 교체된다', () async {
    const storage = FlutterSecureStorage();
    const salt = 'legacy-salt';
    final digest = sha256.convert(utf8.encode('$salt:2468')).toString();
    await storage.write(key: 'app_lock_secret_record', value: '$salt:$digest');

    final service = LockServiceImpl(secureStorage: storage);
    expect(await service.verifySecret('2468'), isTrue);

    final upgraded = await storage.read(key: 'app_lock_secret_record');
    expect(upgraded, startsWith('${PinHasher.algorithm}\$'));
    expect(PinHasher.verify('2468', upgraded!), isTrue);
  });
}
