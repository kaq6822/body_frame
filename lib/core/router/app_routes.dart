/// 라우트 이름/경로 상수.
///
/// 화면 이동 시 `context.goNamed(AppRoutes.<name>, ...)`를 사용하고,
/// 경로 문자열을 하드코딩하지 않는다. 경로 파라미터 키는 [AppParams]에 정의한다.
class AppRoutes {
  AppRoutes._();

  /// 1. 홈 = 연속 세션 촬영 화면.
  ///
  /// 앱을 열면 곧바로 카메라다. 기록과 설정은 이 화면에서 진입한다.
  static const home = 'home';

  // --- 사진 등록 ---
  /// 2. 촬영 결과 일괄 확인 화면.
  static const captureReview = 'capture.review';

  /// 3. 갤러리 사진 등록 화면.
  static const galleryImport = 'capture.import';

  // --- 기록 ---
  /// 4. 촬영 기록 타임라인 화면.
  static const records = 'records';

  /// 5. 촬영 기록 상세 화면.
  static const recordDetail = 'records.detail';

  /// 6. 원본 사진 보기 화면.
  static const photoView = 'records.photo';

  // --- 비교 ---
  /// 7. 비교 날짜 선택 화면.
  static const compareDates = 'compare.dates';

  /// 8. 비교 방향 선택 화면.
  static const compareDirection = 'compare.direction';

  /// 9. 전후 사진 비교 화면.
  static const compareView = 'compare.view';

  /// 10. 비교 이미지 저장 설정 화면.
  static const compareExport = 'compare.export';

  // --- 설정 ---
  /// 11. 앱 설정 화면.
  static const settings = 'settings.home';

  /// 12. 저장 공간 관리 화면.
  static const storage = 'settings.storage';
}

/// 경로 파라미터 키. 안정적 UUID 식별자를 전달한다.
class AppParams {
  AppParams._();

  static const recordId = 'recordId';
  static const photoId = 'photoId';

  /// 방향/날짜 등은 쿼리 파라미터로 전달한다.
  static const direction = 'direction';
  static const beforePhotoId = 'beforePhotoId';
  static const afterPhotoId = 'afterPhotoId';
}
