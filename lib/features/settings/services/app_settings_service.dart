import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/models.dart';
import '../../../core/services/app_logger.dart';

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

  AppSettingsServiceImpl({AppLogger? logger})
      : _logger = logger ?? AppLogger.instance;

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings.fromJson(prefs.getString(_key));
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, settings.toJson());
    _logger.info('settings.save');
  }
}
