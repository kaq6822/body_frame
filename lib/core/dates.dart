/// 촬영일 계산에 필요한 공용 순수 함수.
///
/// 타임라인 경과일과 비교 기간이 같은 규칙을 써야 서머타임 경계에서도 값이
/// 어긋나지 않는다. 화면마다 날짜 공식을 따로 두지 않고 여기만 쓴다.
library;

/// 날짜만 남긴 값. 시각 성분을 버린다.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 두 촬영일 사이의 일수([older] → [newer]).
///
/// 지역 시간의 자정끼리 빼면 서머타임이 낀 구간은 23시간 또는 25시간이 되어
/// `inDays`가 하루를 깎거나 더한다. 날짜만 남긴 뒤에는 시간대가 의미 없으므로
/// UTC 자정으로 옮겨 하루를 항상 24시간으로 고정한다.
///
/// 인자를 바꾸면 값이 같으므로 `daysBetween(a, b) == daysBetween(b, a)`이고,
/// 음수 대신 절댓값이 필요하면 호출부가 `abs()`를 씌운다.
int daysBetween(DateTime older, DateTime newer) {
  final from = dateOnly(older);
  final to = dateOnly(newer);
  return DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
