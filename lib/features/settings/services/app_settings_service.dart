import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/app_logger.dart';

/// [AppSettings] 영속화. shared_preferences에 JSON으로 저장한다.
///
/// 주의: 카메라 화면이 실시간으로 사용하는 격자 설정은 core의
/// `GridSettingsService`(키: `grid_settings`)가 별도로 관리한다. 이 서비스가
/// 저장하는 [AppSettings.defaultGrid]는 설정 화면 표시용이며 충돌을 피하기
/// 위해 다른 저장 키(`app_settings`)를 사용한다.
abstract class AppSettingsService {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class AppSettingsServiceImpl implements AppSettingsService {
  static const String _key = 'app_settings';

  final AppLogger _logger;

  AppSettingsServiceImpl({AppLogger? logger})
    : _logger = logger ?? AppLogger.instance;

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final settings = AppSettings.fromJson(prefs.getString(_key));
      if (!_isValid(settings)) {
        throw const FormatException('앱 설정 범위가 올바르지 않습니다.');
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
    final grid = settings.defaultGrid;
    return grid.opacity.isFinite &&
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
