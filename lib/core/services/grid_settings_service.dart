import 'package:shared_preferences/shared_preferences.dart';

import '../models/grid_settings.dart';
import 'app_logger.dart';

/// 격자 설정 영속화 서비스.
///
/// 격자 설정을 앱 종료 후에도 유지한다.
/// shared_preferences에 JSON으로 저장한다.
///
/// 테스트에서는 `SharedPreferences.setMockInitialValues({})` 후
/// [GridSettingsServiceImpl]를 그대로 사용하면 된다.
abstract class GridSettingsService {
  Future<GridSettings> load();
  Future<void> save(GridSettings settings);
  Future<void> reset();
}

class GridSettingsServiceImpl implements GridSettingsService {
  static const String _key = 'grid_settings';

  final AppLogger _logger;

  GridSettingsServiceImpl({AppLogger? logger})
      : _logger = logger ?? AppLogger.instance;

  @override
  Future<GridSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_key);
    if (source == null) return GridSettings.defaults;
    return GridSettings.fromJson(source);
  }

  @override
  Future<void> save(GridSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, settings.toJson());
    _logger.info('grid.save');
  }

  @override
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _logger.info('grid.reset');
  }
}
