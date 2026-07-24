/// 라우트 이름/경로 상수. MVP.md 12장의 20개 화면.
///
/// 워커는 화면 이동 시 `context.goNamed(AppRoutes.<name>, ...)`를 사용하고,
/// 경로 문자열을 하드코딩하지 않는다. 경로 파라미터 키는 [AppParams]에 정의한다.
class AppRoutes {
  AppRoutes._();

  // --- 회원 관리 ---
  /// 1. 앱 시작 화면.
  static const appStart = 'app.start';

  /// 2. 회원 목록 화면.
  static const membersList = 'members.list';

  /// 3. 회원 등록 화면.
  static const memberAdd = 'members.add';

  /// 4. 회원 상세 화면.
  static const memberDetail = 'members.detail';

  /// 5. 회원 정보 수정 화면.
  static const memberEdit = 'members.edit';

  // --- 사진 관리 ---
  /// 6. 촬영 방향 선택 화면.
  static const captureDirection = 'capture.direction';

  /// 7. 격자 카메라 화면.
  static const captureCamera = 'capture.camera';

  /// 8. 촬영 결과 확인 화면.
  static const captureReview = 'capture.review';

  /// 9. 갤러리 사진 등록 화면.
  static const galleryImport = 'capture.import';

  /// 10. 촬영 기록 상세 화면.
  static const recordDetail = 'records.detail';

  /// 11. 원본 사진 보기 화면.
  static const photoView = 'records.photo';

  // --- 비교 ---
  /// 12. 비교 날짜 선택 화면.
  static const compareDates = 'compare.dates';

  /// 13. 비교 방향 선택 화면.
  static const compareDirection = 'compare.direction';

  /// 14. 전후 사진 비교 화면.
  static const compareView = 'compare.view';

  /// 15. 비교 이미지 저장 설정 화면.
  static const compareExport = 'compare.export';

  // --- 데이터 및 설정 ---
  /// 16. 앱 설정 화면.
  static const settings = 'settings.home';

  /// 17. 앱 잠금 설정 화면.
  static const appLock = 'settings.lock';

  /// 18. 백업 및 복원 화면.
  static const backupRestore = 'settings.backup';

  /// 19. 저장 공간 관리 화면.
  static const storage = 'settings.storage';

  /// 20. 개인정보 및 이용 안내 화면.
  static const privacyInfo = 'settings.privacy';
}

/// 경로 파라미터 키. MVP.md 19장: 안정적 uuid 식별자를 파라미터로 전달한다.
class AppParams {
  AppParams._();

  static const memberId = 'memberId';
  static const recordId = 'recordId';
  static const photoId = 'photoId';

  /// 방향/날짜 등은 쿼리 파라미터로 전달한다.
  static const direction = 'direction';
  static const beforePhotoId = 'beforePhotoId';
  static const afterPhotoId = 'afterPhotoId';
}
