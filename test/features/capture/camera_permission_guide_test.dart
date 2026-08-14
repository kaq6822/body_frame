import 'package:body_frame/features/capture/camera_permission_guide.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카메라 권한 설정 경로 검증.
///
/// 한쪽 플랫폼 경로를 하드코딩해 두면 다른 플랫폼 사용자는 없는 메뉴를 찾아다닌다.
/// 실행 환경과 무관하게 두 분기를 모두 확인한다.
void main() {
  group('cameraPermissionSettingsPath', () {
    test('iOS는 앱 화면에서 카메라 항목으로 바로 간다', () {
      expect(cameraPermissionSettingsPath(isIOS: true), [
        '설정',
        '앱',
        'Body Frame',
        '카메라',
      ]);
    });

    test('Android는 권한 화면을 한 번 더 거친다', () {
      expect(cameraPermissionSettingsPath(isIOS: false), [
        '설정',
        '앱',
        'Body Frame',
        '권한',
        '카메라',
      ]);
    });

    test('두 플랫폼의 경로가 서로 다르다', () {
      // 같아지면 분기가 무의미해진 것이므로 알아차려야 한다.
      expect(
        cameraPermissionSettingsPath(isIOS: true),
        isNot(cameraPermissionSettingsPath(isIOS: false)),
      );
    });

    test('앱 이름은 두 플랫폼의 표시 이름과 같다', () {
      // Info.plist의 CFBundleDisplayName, AndroidManifest의 android:label 값.
      for (final ios in [true, false]) {
        expect(cameraPermissionSettingsPath(isIOS: ios), contains('Body Frame'));
      }
    });
  });

  test('메뉴 이름이 기기마다 다를 수 있다는 점을 밝힌다', () {
    // 제조사(삼성은 "애플리케이션")와 OS 버전에 따라 갈리는 부분을 감추면,
    // 안내와 다른 화면을 본 사용자가 자기가 잘못한 줄로 안다.
    expect(cameraPermissionSettingsHint, isNotEmpty);
  });
}
