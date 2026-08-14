import 'dart:io';

/// 기기 설정에서 카메라 권한까지 가는 경로. **플랫폼마다 다르다.**
///
/// iOS는 앱 화면 안에 권한 항목이 바로 있고, Android는 앱 정보 아래 권한 화면을
/// 한 번 더 거친다. 한쪽 경로를 하드코딩해 두면 다른 플랫폼 사용자는 없는 메뉴를
/// 찾아다니게 된다.
///
/// [isIOS]는 테스트에서 두 분기를 모두 확인하려고 열어 둔 것이다. 비워 두면 실행
/// 중인 플랫폼을 따른다.
List<String> cameraPermissionSettingsPath({bool? isIOS}) {
  final ios = isIOS ?? Platform.isIOS;
  return ios
      ? const ['설정', '앱', 'Body Frame', '카메라']
      : const ['설정', '앱', 'Body Frame', '권한', '카메라'];
}

/// 경로 안내 위에 붙는 한 줄.
///
/// 메뉴 이름이 제조사와 OS 버전에 따라 갈린다는 점을 밝힌다. 삼성은 "앱" 대신
/// "애플리케이션"으로, iOS 17 이하는 "앱" 단계 없이 목록에서 바로 앱을 고른다.
/// 정확히 맞출 수 없는 부분을 감추면, 안내와 다른 화면을 본 사용자가 자기가
/// 잘못한 줄로 안다.
const String cameraPermissionSettingsHint = '기기에 따라 메뉴 이름이 조금 다를 수 있어요.';
