/// 비교 방향 선택 화면으로 넘기는 쿼리 파라미터 키.
/// [AppParams]에는 촬영 기록 id 쌍이 정의되어 있지 않아 이 feature 안에서만
/// 쓰는 이름을 별도로 둔다(경로 문자열 자체는 여전히 goNamed로만 다룬다).
class CompareQueryKeys {
  CompareQueryKeys._();
  static const beforeRecordId = 'beforeRecordId';
  static const afterRecordId = 'afterRecordId';
}
