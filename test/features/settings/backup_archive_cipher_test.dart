import 'dart:async';
import 'dart:typed_data';

import 'package:body_frame/features/settings/services/backup_archive_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

const _password = 'correct horse battery staple';

void main() {
  late BackupArchiveCipher cipher;

  setUp(() {
    var randomByte = 0;
    cipher = BackupArchiveCipherImpl(
      kdfPolicy: const BackupKdfPolicy(
        memoryKiB: 32,
        iterations: 1,
        minimumAcceptedMemoryKiB: 8,
        maximumAcceptedMemoryKiB: 1024,
        minimumAcceptedIterations: 1,
        maximumAcceptedIterations: 2,
      ),
      randomBytes: (length) {
        final bytes = Uint8List(length);
        for (var i = 0; i < length; i++) {
          bytes[i] = randomByte++ & 0xff;
        }
        return bytes;
      },
      runInBackground: false,
    );
  });

  test('Argon2id와 AES-256-GCM 컨테이너가 원문을 인증 암호화하고 복호화한다', () async {
    final plaintext = Uint8List.fromList([0x50, 0x4B, 3, 4, 1, 2, 3]);

    final encrypted = await cipher.encrypt(plaintext, password: _password);

    expect(cipher.isEncrypted(encrypted), isTrue);
    expect(encrypted, isNot(plaintext));
    expect(
      encrypted.length,
      cipher.maximumContainerBytesForPlaintextLimit(plaintext.length),
    );
    expect(await cipher.decrypt(encrypted, password: _password), plaintext);
  });

  test('비밀번호 누락과 약한 생성 비밀번호를 거부한다', () async {
    await expectLater(
      cipher.encrypt([1, 2, 3], password: ''),
      throwsA(isA<WeakBackupPasswordException>()),
    );
    await expectLater(
      cipher.encrypt([1, 2, 3], password: 'too-short'),
      throwsA(isA<WeakBackupPasswordException>()),
    );

    final encrypted = await cipher.encrypt([1, 2, 3], password: _password);
    await expectLater(
      cipher.decrypt(encrypted, password: null),
      throwsA(isA<BackupPasswordRequiredException>()),
    );
    await expectLater(
      cipher.decrypt(encrypted, password: ''),
      throwsA(isA<BackupPasswordRequiredException>()),
    );
  });

  test('잘못된 비밀번호는 인증 전에 평문을 반환하지 않는다', () async {
    final encrypted = await cipher.encrypt([1, 2, 3, 4], password: _password);

    await expectLater(
      cipher.decrypt(encrypted, password: 'this password is definitely wrong'),
      throwsA(isA<BackupAuthenticationException>()),
    );
  });

  test('헤더, 암호문, 인증 태그 변조를 모두 감지한다', () async {
    final encrypted = await cipher.encrypt(
      List<int>.generate(128, (index) => index),
      password: _password,
    );

    final headerTampered = Uint8List.fromList(encrypted);
    // 허용 범위 안에서 Argon2id 반복 횟수만 1 -> 2로 바꿔 AAD/KDF 변조를 검증한다.
    headerTampered[19] = 2;

    final cipherTextTampered = Uint8List.fromList(encrypted);
    cipherTextTampered[60] ^= 0x01;

    final tagTampered = Uint8List.fromList(encrypted);
    tagTampered[tagTampered.length - 1] ^= 0x01;

    for (final tampered in [headerTampered, cipherTextTampered, tagTampered]) {
      await expectLater(
        cipher.decrypt(tampered, password: _password),
        throwsA(isA<BackupAuthenticationException>()),
      );
    }
  });

  test('과도한 KDF 비용이나 잘린 컨테이너를 파싱 단계에서 거부한다', () async {
    final encrypted = await cipher.encrypt([1, 2, 3, 4], password: _password);
    final excessiveCost = Uint8List.fromList(encrypted);
    // memoryKiB uint32를 허용 상한보다 큰 1025로 변경한다.
    excessiveCost[12] = 0;
    excessiveCost[13] = 0;
    excessiveCost[14] = 4;
    excessiveCost[15] = 1;

    await expectLater(
      cipher.decrypt(excessiveCost, password: _password),
      throwsA(isA<EncryptedBackupFormatException>()),
    );
    await expectLater(
      cipher.decrypt(
        Uint8List.sublistView(encrypted, 0, 20),
        password: _password,
      ),
      throwsA(isA<EncryptedBackupFormatException>()),
    );
  });

  test(
    '운영 기본 Argon2id/AES-GCM은 background isolate에서 실행되어 event loop를 막지 않는다',
    () async {
      final productionCipher = BackupArchiveCipherImpl(
        maxPlaintextBytes: 2 * 1024 * 1024,
      );
      final plaintext = Uint8List(1024 * 1024);
      var eventLoopTicks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => eventLoopTicks++,
      );
      try {
        final encrypted = await productionCipher.encrypt(
          plaintext,
          password: _password,
        );
        expect(eventLoopTicks, greaterThan(0));
        expect(
          await productionCipher.decrypt(encrypted, password: _password),
          plaintext,
        );
        await expectLater(
          productionCipher.decrypt(
            encrypted,
            password: 'this password is definitely wrong',
          ),
          throwsA(isA<BackupAuthenticationException>()),
        );
      } finally {
        timer.cancel();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
