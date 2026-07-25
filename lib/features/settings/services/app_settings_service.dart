import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/photo_storage_service.dart';

/// [AppSettings] 영속화. shared_preferences에 JSON으로 저장한다.
///
/// 주의: 카메라 화면이 실시간으로 사용하는 격자 설정은 core의
/// `GridSettingsService`(키: `grid_settings`)가 별도로 관리한다. 이 서비스가
/// 저장하는 [AppSettings.defaultGrid]는 백업 스냅샷/설정 화면 표시용이며
/// 충돌을 피하기 위해 다른 저장 키(`app_settings`)를 사용한다.
abstract class AppSettingsService {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class AppSettingsServiceImpl implements AppSettingsService {
  static const String _key = 'app_settings';

  final AppLogger _logger;
  final PhotoStorageService? _storage;

  AppSettingsServiceImpl({AppLogger? logger, PhotoStorageService? storage})
    : _logger = logger ?? AppLogger.instance,
      _storage = storage;

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      var settings = AppSettings.fromJson(prefs.getString(_key));
      if (!_isValid(settings)) {
        throw const FormatException('앱 설정 범위가 올바르지 않습니다.');
      }
      final logoPath = settings.studioLogoPath;
      final storage = _storage;
      if (logoPath != null && logoPath.isNotEmpty && storage != null) {
        try {
          final relative = await storage.toStoredPath(logoPath);
          if (relative != logoPath) {
            settings = settings.copyWith(studioLogoPath: relative);
            await prefs.setString(_key, settings.toJson());
          }
        } catch (_) {
          // 외부/손상 경로를 계속 열지 않도록 제거한다. 실제 파일은 앱 관리
          // 저장소 밖일 수 있으므로 여기서 삭제하지 않는다.
          settings = settings.copyWith(clearStudioLogoPath: true);
          await prefs.setString(_key, settings.toJson());
          _logger.warn('settings.studioLogo.invalid');
        }
      }
      return settings;
    } catch (_) {
      _logger.warn('settings.load.invalid');
      return AppSettings.defaults;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    if (!_isValid(settings)) {
      throw ArgumentError.value(settings, 'settings', '안전한 앱 설정이어야 합니다.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, settings.toJson());
    _logger.info('settings.save');
  }

  bool _isValid(AppSettings settings) {
    const autoLockOptions = {0, 15, 30, 60, 300};
    final grid = settings.defaultGrid;
    return autoLockOptions.contains(settings.autoLockSeconds) &&
        grid.opacity.isFinite &&
        grid.opacity >= 0 &&
        grid.opacity <= 1 &&
        grid.lineWidth.isFinite &&
        grid.lineWidth > 0 &&
        grid.spacing.isFinite &&
        grid.spacing > 0 &&
        grid.colorValue >= 0 &&
        grid.colorValue <= 0xFFFFFFFF;
  }
}
