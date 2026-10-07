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
    try {
      final settings = GridSettings.fromJson(source);
      if (!_isValid(settings)) {
        throw const FormatException('격자 설정 범위가 올바르지 않습니다.');
      }
      return settings;
    } catch (_) {
      // 손상된 로컬 설정 때문에 카메라/페인터가 열리지 않는 대신 안전한
      // 기본값으로 복구한다. 다음 저장 시 정상 JSON으로 덮어쓴다.
      _logger.warn('grid.load.invalid');
      return GridSettings.defaults;
    }
  }

  @override
  Future<void> save(GridSettings settings) async {
    if (!_isValid(settings)) {
      throw ArgumentError.value(settings, 'settings', '안전한 격자 설정이어야 합니다.');
    }
    final prefs = await SharedPreferences.getInstance();
    // setString/remove가 false를 돌려도 저장은 실패한 것이다. 성공으로 처리하면
    // 재시도할 단서가 사라지고 설정은 조용히 이전 값으로 남는다.
    final saved = await prefs.setString(_key, settings.toJson());
    if (!saved) {
      throw StateError('격자 설정을 shared_preferences에 저장하지 못했습니다.');
    }
    _logger.info('grid.save');
  }

  @override
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    final removed = await prefs.remove(_key);
    if (!removed) {
      throw StateError('격자 설정을 shared_preferences에서 지우지 못했습니다.');
    }
    _logger.info('grid.reset');
  }

  bool _isValid(GridSettings settings) {
    return settings.opacity.isFinite &&
        settings.opacity >= 0 &&
        settings.opacity <= 1 &&
        settings.lineWidth.isFinite &&
        settings.lineWidth > 0 &&
        settings.spacing.isFinite &&
        settings.spacing > 0 &&
        settings.colorValue >= 0 &&
        settings.colorValue <= 0xFFFFFFFF;
  }
}
