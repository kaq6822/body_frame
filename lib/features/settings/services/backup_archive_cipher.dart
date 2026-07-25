import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String encryptedBackupFileExtension = 'bfbackup';

typedef BackupRandomBytes = Uint8List Function(int length);

class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();

  @override
  String toString() => '백업 비밀번호가 필요합니다';
}

class WeakBackupPasswordException implements Exception {
  const WeakBackupPasswordException();

  @override
  String toString() => '백업 비밀번호가 보안 기준을 충족하지 않습니다';
}

class BackupAuthenticationException implements Exception {
  const BackupAuthenticationException();

  @override
  String toString() => '백업 비밀번호가 틀렸거나 파일이 변조되었습니다';
}

class EncryptedBackupFormatException implements Exception {
  final String message;

  const EncryptedBackupFormatException(this.message);

  @override
  String toString() => message;
}

/// 새 백업에 적용할 Argon2id 비용과 읽을 수 있는 컨테이너 비용 범위.
///
/// 기본값은 cryptography의 Argon2id 문서가 인용하는 OWASP 기준
/// (19 MiB, 2회, 병렬도 1)이다. 테스트는 작은 비용과 그에 맞는 허용 범위를
/// 주입할 수 있다.
class BackupKdfPolicy {
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int minimumAcceptedMemoryKiB;
  final int maximumAcceptedMemoryKiB;
  final int minimumAcceptedIterations;
  final int maximumAcceptedIterations;
  final int maximumAcceptedParallelism;

  const BackupKdfPolicy({
    this.memoryKiB = 19 * 1024,
    this.iterations = 2,
    this.parallelism = 1,
    this.minimumAcceptedMemoryKiB = 19 * 1024,
    this.maximumAcceptedMemoryKiB = 64 * 1024,
    this.minimumAcceptedIterations = 2,
    this.maximumAcceptedIterations = 5,
    this.maximumAcceptedParallelism = 2,
  });

  void validate() {
    if (parallelism < 1 ||
        parallelism > maximumAcceptedParallelism ||
        memoryKiB < minimumAcceptedMemoryKiB ||
        memoryKiB > maximumAcceptedMemoryKiB ||
        memoryKiB < 8 * parallelism ||
        iterations < minimumAcceptedIterations ||
        iterations > maximumAcceptedIterations ||
        minimumAcceptedMemoryKiB < 8 ||
        minimumAcceptedMemoryKiB > maximumAcceptedMemoryKiB ||
        minimumAcceptedIterations < 1 ||
        minimumAcceptedIterations > maximumAcceptedIterations) {
      throw ArgumentError('Argon2id 비용 설정이 올바르지 않습니다');
    }
  }

  bool accepts({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) {
    return parallelism >= 1 &&
        parallelism <= maximumAcceptedParallelism &&
        memoryKiB >= minimumAcceptedMemoryKiB &&
        memoryKiB <= maximumAcceptedMemoryKiB &&
        memoryKiB >= 8 * parallelism &&
        iterations >= minimumAcceptedIterations &&
        iterations <= maximumAcceptedIterations;
  }
}

class BackupPasswordPolicy {
  final int minimumLength;
  final int maximumLength;

  const BackupPasswordPolicy({
    this.minimumLength = 12,
    this.maximumLength = 256,
  });

  void validateForEncryption(String password) {
    final length = password.runes.length;
    if (password.trim().isEmpty ||
        length < minimumLength ||
        length > maximumLength) {
      throw const WeakBackupPasswordException();
    }
  }

  void validateForDecryption(String? password) {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    if (password.runes.length > maximumLength) {
      throw const BackupAuthenticationException();
    }
  }
}

abstract class BackupArchiveCipher {
  /// [plaintextLimit]까지의 평문 백업을 담는 암호화 컨테이너의 최대 바이트 수.
  ///
  /// 호출자는 헤더·salt·nonce·인증 태그의 크기를 별도로 복제하지 않고 이
  /// 계약을 사용해 암호화 입력 파일의 크기 상한을 계산한다.
  int maximumContainerBytesForPlaintextLimit(int plaintextLimit);

  bool isEncrypted(List<int> bytes);

  void validatePasswordForEncryption(String password);

  Future<Uint8List> encrypt(List<int> plaintext, {required String password});

  Future<Uint8List> decrypt(List<int> encrypted, {required String? password});
}

/// `BFBACKUP` 전용 컨테이너.
///
/// 고정 헤더와 salt/nonce 전체를 AES-GCM AAD로 인증한다. 헤더에는 Argon2id
/// 비용이 들어가므로 비용 파라미터를 바꾸는 변조도 인증 실패한다.
class BackupArchiveCipherImpl implements BackupArchiveCipher {
  static const _magic = <int>[
    0x42, // B
    0x46, // F
    0x42, // B
    0x41, // A
    0x43, // C
    0x4B, // K
    0x55, // U
    0x50, // P
  ];
  static const _containerVersion = 1;
  static const _argon2idAlgorithm = 1;
  static const _aes256GcmAlgorithm = 1;
  static const _fixedHeaderLength = 32;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _keyLength = 32;

  final BackupKdfPolicy kdfPolicy;
  final BackupPasswordPolicy passwordPolicy;
  final int maxPlaintextBytes;
  final BackupRandomBytes _randomBytes;
  final AesGcm _cipher;
  final bool _runInBackground;

  BackupArchiveCipherImpl({
    this.kdfPolicy = const BackupKdfPolicy(),
    this.passwordPolicy = const BackupPasswordPolicy(),
    this.maxPlaintextBytes = 512 * 1024 * 1024,
    BackupRandomBytes? randomBytes,
    AesGcm? cipher,
    bool runInBackground = true,
  }) : _randomBytes = randomBytes ?? _secureRandomBytes,
       _cipher = cipher ?? AesGcm.with256bits(),
       _runInBackground = runInBackground {
    kdfPolicy.validate();
    if (maxPlaintextBytes <= 0) {
      throw ArgumentError.value(maxPlaintextBytes, 'maxPlaintextBytes');
    }
    if (runInBackground && (randomBytes != null || cipher != null)) {
      throw ArgumentError(
        '사용자 지정 암호/난수 구현은 runInBackground=false에서만 사용할 수 있습니다',
      );
    }
  }

  @override
  int maximumContainerBytesForPlaintextLimit(int plaintextLimit) {
    if (plaintextLimit <= 0) {
      throw ArgumentError.value(plaintextLimit, 'plaintextLimit');
    }
    final acceptedPlaintextLimit = plaintextLimit < maxPlaintextBytes
        ? plaintextLimit
        : maxPlaintextBytes;
    return acceptedPlaintextLimit +
        _fixedHeaderLength +
        _saltLength +
        _nonceLength +
        _macLength;
  }

  @override
  bool isEncrypted(List<int> bytes) {
    if (bytes.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  @override
  void validatePasswordForEncryption(String password) {
    passwordPolicy.validateForEncryption(password);
  }

  @override
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String password,
  }) async {
    validatePasswordForEncryption(password);
    if (plaintext.isEmpty || plaintext.length > maxPlaintextBytes) {
      throw const EncryptedBackupFormatException('암호화할 백업 크기가 허용 범위를 벗어납니다');
    }
    if (!_runInBackground) {
      return _encryptDirect(plaintext, password: password);
    }

    final workerInput = plaintext is Uint8List
        ? plaintext
        : Uint8List.fromList(plaintext);
    final workerKdfPolicy = kdfPolicy;
    final workerPasswordPolicy = passwordPolicy;
    final workerMaxPlaintextBytes = maxPlaintextBytes;
    return Isolate.run(() {
      return BackupArchiveCipherImpl(
        kdfPolicy: workerKdfPolicy,
        passwordPolicy: workerPasswordPolicy,
        maxPlaintextBytes: workerMaxPlaintextBytes,
        runInBackground: false,
      )._encryptDirect(workerInput, password: password);
    });
  }

  Future<Uint8List> _encryptDirect(
    List<int> plaintext, {
    required String password,
  }) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    if (salt.length != _saltLength || nonce.length != _nonceLength) {
      throw StateError('보안 난수 생성 결과 길이가 올바르지 않습니다');
    }
    final header = _buildHeader(
      memoryKiB: kdfPolicy.memoryKiB,
      iterations: kdfPolicy.iterations,
      parallelism: kdfPolicy.parallelism,
      plaintextLength: plaintext.length,
      salt: salt,
      nonce: nonce,
    );

    final secretKey = await _deriveKey(
      password: password,
      salt: salt,
      memoryKiB: kdfPolicy.memoryKiB,
      iterations: kdfPolicy.iterations,
      parallelism: kdfPolicy.parallelism,
    );
    try {
      final box = await _cipher.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
        aad: header,
      );
      if (box.mac.bytes.length != _macLength ||
          box.cipherText.length != plaintext.length) {
        throw StateError('AES-GCM 출력 길이가 올바르지 않습니다');
      }
      final result = Uint8List(
        header.length + box.cipherText.length + box.mac.bytes.length,
      );
      result.setRange(0, header.length, header);
      result.setRange(
        header.length,
        header.length + box.cipherText.length,
        box.cipherText,
      );
      result.setRange(
        header.length + box.cipherText.length,
        result.length,
        box.mac.bytes,
      );
      return result;
    } finally {
      secretKey.destroy();
    }
  }

  @override
  Future<Uint8List> decrypt(
    List<int> encrypted, {
    required String? password,
  }) async {
    passwordPolicy.validateForDecryption(password);
    if (!isEncrypted(encrypted)) {
      throw const EncryptedBackupFormatException('암호화 백업 헤더가 없습니다');
    }
    if (!_runInBackground) {
      return _decryptDirect(encrypted, password: password!);
    }

    final workerInput = encrypted is Uint8List
        ? encrypted
        : Uint8List.fromList(encrypted);
    final workerKdfPolicy = kdfPolicy;
    final workerPasswordPolicy = passwordPolicy;
    final workerMaxPlaintextBytes = maxPlaintextBytes;
    return Isolate.run(() {
      return BackupArchiveCipherImpl(
        kdfPolicy: workerKdfPolicy,
        passwordPolicy: workerPasswordPolicy,
        maxPlaintextBytes: workerMaxPlaintextBytes,
        runInBackground: false,
      )._decryptDirect(workerInput, password: password!);
    });
  }

  Future<Uint8List> _decryptDirect(
    List<int> encrypted, {
    required String password,
  }) async {
    final bytes = encrypted is Uint8List
        ? encrypted
        : Uint8List.fromList(encrypted);
    final parsed = _parseHeader(bytes);

    final secretKey = await _deriveKey(
      password: password,
      salt: parsed.salt,
      memoryKiB: parsed.memoryKiB,
      iterations: parsed.iterations,
      parallelism: parsed.parallelism,
    );
    try {
      final box = SecretBox(
        Uint8List.sublistView(
          bytes,
          parsed.headerLength,
          bytes.length - _macLength,
        ),
        nonce: parsed.nonce,
        mac: Mac(Uint8List.sublistView(bytes, bytes.length - _macLength)),
      );
      try {
        final plaintext = await _cipher.decrypt(
          box,
          secretKey: secretKey,
          aad: Uint8List.sublistView(bytes, 0, parsed.headerLength),
        );
        if (plaintext.length != parsed.plaintextLength) {
          throw const BackupAuthenticationException();
        }
        return Uint8List.fromList(plaintext);
      } on SecretBoxAuthenticationError {
        throw const BackupAuthenticationException();
      }
    } finally {
      secretKey.destroy();
    }
  }

  Future<SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) {
    return Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: _keyLength,
    ).deriveKeyFromPassword(password: password, nonce: salt);
  }

  Uint8List _buildHeader({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required int plaintextLength,
    required Uint8List salt,
    required Uint8List nonce,
  }) {
    final header = Uint8List(_fixedHeaderLength + _saltLength + _nonceLength);
    header.setRange(0, _magic.length, _magic);
    header[8] = _containerVersion;
    header[9] = _argon2idAlgorithm;
    header[10] = _aes256GcmAlgorithm;
    header[11] = 0;
    final data = ByteData.sublistView(header);
    data.setUint32(12, memoryKiB, Endian.big);
    data.setUint32(16, iterations, Endian.big);
    header[20] = parallelism;
    header[21] = _saltLength;
    header[22] = _nonceLength;
    header[23] = _macLength;
    data.setUint64(24, plaintextLength, Endian.big);
    header.setRange(_fixedHeaderLength, _fixedHeaderLength + _saltLength, salt);
    header.setRange(_fixedHeaderLength + _saltLength, header.length, nonce);
    return header;
  }

  _ParsedBackupHeader _parseHeader(Uint8List bytes) {
    final minimumLength =
        _fixedHeaderLength + _saltLength + _nonceLength + _macLength;
    if (bytes.length < minimumLength) {
      throw const EncryptedBackupFormatException('암호화 백업이 잘렸습니다');
    }
    if (bytes[8] != _containerVersion ||
        bytes[9] != _argon2idAlgorithm ||
        bytes[10] != _aes256GcmAlgorithm ||
        bytes[11] != 0 ||
        bytes[21] != _saltLength ||
        bytes[22] != _nonceLength ||
        bytes[23] != _macLength) {
      throw const EncryptedBackupFormatException('지원하지 않는 암호화 백업 형식입니다');
    }

    final data = ByteData.sublistView(bytes);
    final memoryKiB = data.getUint32(12, Endian.big);
    final iterations = data.getUint32(16, Endian.big);
    final parallelism = bytes[20];
    final plaintextLength = data.getUint64(24, Endian.big);
    if (!kdfPolicy.accepts(
          memoryKiB: memoryKiB,
          iterations: iterations,
          parallelism: parallelism,
        ) ||
        plaintextLength <= 0 ||
        plaintextLength > maxPlaintextBytes) {
      throw const EncryptedBackupFormatException(
        '암호화 백업 보안 파라미터가 허용 범위를 벗어납니다',
      );
    }

    final headerLength = _fixedHeaderLength + _saltLength + _nonceLength;
    final cipherTextLength = bytes.length - headerLength - _macLength;
    if (cipherTextLength != plaintextLength) {
      throw const EncryptedBackupFormatException('암호화 백업 길이가 올바르지 않습니다');
    }
    return _ParsedBackupHeader(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      plaintextLength: plaintextLength,
      headerLength: headerLength,
      salt: Uint8List.sublistView(
        bytes,
        _fixedHeaderLength,
        _fixedHeaderLength + _saltLength,
      ),
      nonce: Uint8List.sublistView(
        bytes,
        _fixedHeaderLength + _saltLength,
        headerLength,
      ),
    );
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    final result = Uint8List(length);
    for (var i = 0; i < result.length; i++) {
      result[i] = random.nextInt(256);
    }
    return result;
  }
}

class _ParsedBackupHeader {
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int plaintextLength;
  final int headerLength;
  final Uint8List salt;
  final Uint8List nonce;

  const _ParsedBackupHeader({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.plaintextLength,
    required this.headerLength,
    required this.salt,
    required this.nonce,
  });
}
