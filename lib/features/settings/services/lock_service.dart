import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/services/app_logger.dart';
import 'pin_hasher.dart';

/// 앱 잠금(PIN·비밀번호·생체 인증) 서비스.
///
/// PIN/비밀번호 원문은 저장하지 않고 [PinHasher]로 만든 salt+해시만
/// flutter_secure_storage에 보관한다.
abstract class LockService {
  Future<bool> hasSecret();

  /// PIN 또는 비밀번호를 설정/변경한다.
  Future<void> setSecret(String secret);

  /// 입력값이 저장된 비밀과 일치하는지 검증한다.
  Future<bool> verifySecret(String secret);

  /// 저장된 비밀을 삭제한다(잠금 해제).
  Future<void> clearSecret();

  /// 기기가 생체 인증을 지원하고 사용 가능한지.
  Future<bool> isBiometricAvailable();

  /// 생체 인증을 실행한다. 취소/실패 시 false.
  Future<bool> authenticateWithBiometrics({String? reason});
}

class LockServiceImpl implements LockService {
  static const String _secretKey = 'app_lock_secret_record';

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;
  final AppLogger _logger;

  LockServiceImpl({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
    AppLogger? logger,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              // 기기 잠금 해제 이후에만 접근 가능 + 백업/기기 이전에서 제외(iOS),
              // EncryptedSharedPreferences 사용(Android).
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            ),
        _localAuth = localAuth ?? LocalAuthentication(),
        _logger = logger ?? AppLogger.instance;

  @override
  Future<bool> hasSecret() async {
    final v = await _secureStorage.read(key: _secretKey);
    return v != null && v.isNotEmpty;
  }

  @override
  Future<void> setSecret(String secret) async {
    final record = PinHasher.createRecord(secret);
    await _secureStorage.write(key: _secretKey, value: record);
    _logger.phase('lock.secret', LogPhase.success, context: {'action': 'set'});
  }

  @override
  Future<bool> verifySecret(String secret) async {
    final record = await _secureStorage.read(key: _secretKey);
    if (record == null) return false;
    final ok = PinHasher.verify(secret, record);
    _logger.phase(
      'lock.secret',
      ok ? LogPhase.success : LogPhase.failure,
      context: {'action': 'verify'},
    );
    return ok;
  }

  @override
  Future<void> clearSecret() async {
    await _secureStorage.delete(key: _secretKey);
    _logger.phase('lock.secret', LogPhase.success, context: {'action': 'clear'});
  }

  @override
  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (e) {
      _logger.warn('lock.biometric.unavailable');
      return false;
    }
  }

  @override
  Future<bool> authenticateWithBiometrics({String? reason}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason ?? '체형 기록에 접근하려면 인증이 필요합니다',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      _logger.phase(
        'lock.biometric',
        ok ? LogPhase.success : LogPhase.failure,
      );
      return ok;
    } catch (e) {
      _logger.error('lock.biometric.failure', err: e);
      return false;
    }
  }
}
