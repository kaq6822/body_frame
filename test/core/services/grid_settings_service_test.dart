import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('손상되거나 안전 범위를 벗어난 격자 설정은 기본값으로 복구한다', () async {
    for (final source in [
      '{"visible":true,"opacity":"invalid"}',
      '{"visible":true,"opacity":2,"lineWidth":1,"spacing":40,'
          '"colorValue":4294967295}',
      '{"visible":true,"opacity":0.5,"lineWidth":0,"spacing":40,'
          '"colorValue":4294967295}',
    ]) {
      SharedPreferences.setMockInitialValues({'grid_settings': source});

      final loaded = await GridSettingsServiceImpl().load();

      expect(loaded, GridSettings.defaults);
    }
  });

  test('안전 범위를 벗어난 격자 설정은 저장하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});

    await expectLater(
      GridSettingsServiceImpl().save(const GridSettings(spacing: 0)),
      throwsArgumentError,
    );
  });
}
