/// 앱 이름과 버전 표시값.
///
/// 새 의존성이나 `--dart-define` 없이 화면에 버전을 보여 주려고 pubspec.yaml의
/// `version`과 같은 값을 상수로 둔다. 둘이 어긋나면 테스트
/// (`test/core/app_info_test.dart`)가 실패하므로 버전을 올릴 때 함께 바꾼다.
class AppInfo {
  AppInfo._();

  static const name = 'BodyMark';

  /// pubspec `version`의 `+` 앞부분.
  static const version = '1.0.0';

  /// pubspec `version`의 `+` 뒷부분.
  static const buildNumber = 1;
}
