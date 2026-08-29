import '../../core/models/models.dart';
import 'providers/records_providers.dart';

/// 타임라인 한 행. 화면은 이 값만 읽어 그린다.
class TimelineRow {
  final RecordWithPhotos entry;

  /// 같은 대상의 직전(더 오래된) 기록과의 간격(일). 직전 기록이 없으면 null.
  final int? daysSincePrevious;

  /// 이 행 위에 붙일 월 헤더. 같은 달이 이어지면 null.
  final String? monthHeader;

  /// 같은 촬영일에 기록이 여러 건일 때 이 기록이 그중 몇 번째 촬영인지
  /// (오래된 것부터 1). 그날 기록이 하나뿐이면 null.
  final int? sameDayOrdinal;

  /// 같은 촬영일의 총 기록 수. [sameDayOrdinal]이 null이면 null.
  final int? sameDayTotal;

  const TimelineRow({
    required this.entry,
    this.daysSincePrevious,
    this.monthHeader,
    this.sameDayOrdinal,
    this.sameDayTotal,
  });

  PhotoRecord get record => entry.record;
}

/// 방향 모아보기 한 항목.
class DirectionRow {
  final PhotoRecord record;
  final BodyPhoto photo;

  /// 같은 방향의 직전 사진과의 간격(일). 직전 사진이 없으면 null.
  final int? daysSincePrevious;

  const DirectionRow({
    required this.record,
    required this.photo,
    this.daysSincePrevious,
  });
}

/// 라벨을 비교 가능한 형태로 정규화한다. 공백만 있는 라벨은 본인 기록으로 본다.
String? normalizeLabel(String? label) {
  final trimmed = label?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// 날짜만 남긴 값. 경과일은 시각이 아니라 날짜 차이로 센다.
///
/// 같은 달력 날짜끼리 묶는 용도이므로 기기 지역 시간대를 그대로 쓴다.
DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 두 촬영일 사이의 일수. 시각 성분과 서머타임 영향을 받지 않게 날짜로 자른다.
///
/// 지역 시간의 자정끼리 빼면 서머타임이 낀 구간은 23시간 또는 25시간이 되어
/// `inDays`가 하루를 깎거나 더한다. 날짜만 남긴 뒤에는 시간대가 의미 없으므로
/// UTC 자정으로 옮겨 하루를 항상 24시간으로 고정한다.
int daysBetween(DateTime older, DateTime newer) {
  final from = _dateOnly(older);
  final to = _dateOnly(newer);
  return DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

/// 타임라인 행 목록을 만든다.
///
/// [entries]는 촬영일 최신순으로 정렬돼 있다고 가정한다([timelineProvider]가
/// 그렇게 준다). 경과일은 **같은 대상 라벨끼리만** 계산한다. 본인 기록 사이에
/// 다른 사람 기록이 끼어도 간격이 어긋나지 않아야 하기 때문이다.
///
/// 촬영 한 건이 기록 하나이므로 같은 날 여러 건이 나란히 놓일 수 있다. 그때는
/// 카드 제목이 똑같아지므로 몇 번째 촬영인지 함께 세어 둔다.
List<TimelineRow> buildTimelineRows(List<RecordWithPhotos> entries) {
  final rows = <TimelineRow>[];

  final totalsByDay = <DateTime, int>{};
  for (final entry in entries) {
    final day = _dateOnly(entry.record.shotAt);
    totalsByDay[day] = (totalsByDay[day] ?? 0) + 1;
  }
  final seenByDay = <DateTime, int>{};

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final label = normalizeLabel(entry.record.label);

    // 같은 라벨의 직전(더 오래된) 기록을 뒤쪽에서 찾는다.
    int? days;
    for (var j = i + 1; j < entries.length; j++) {
      if (normalizeLabel(entries[j].record.label) != label) continue;
      days = daysBetween(entries[j].record.shotAt, entry.record.shotAt);
      break;
    }

    final shotAt = entry.record.shotAt;
    final previousShotAt = i == 0 ? null : entries[i - 1].record.shotAt;
    final startsMonth =
        previousShotAt == null ||
        previousShotAt.year != shotAt.year ||
        previousShotAt.month != shotAt.month;

    // 최신순으로 훑고 있으므로 오래된 촬영이 1번이 되도록 뒤집어 센다.
    final day = _dateOnly(shotAt);
    final sameDayTotal = totalsByDay[day] ?? 1;
    final seen = (seenByDay[day] ?? 0) + 1;
    seenByDay[day] = seen;

    rows.add(
      TimelineRow(
        entry: entry,
        daysSincePrevious: days,
        monthHeader: startsMonth ? formatMonthHeader(shotAt) : null,
        sameDayOrdinal: sameDayTotal > 1 ? sameDayTotal - seen + 1 : null,
        sameDayTotal: sameDayTotal > 1 ? sameDayTotal : null,
      ),
    );
  }

  return rows;
}

/// 월 헤더 문구.
String formatMonthHeader(DateTime date) => '${date.year}년 ${date.month}월';

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 카드 제목용 날짜 문구.
///
/// `DateFormat('M월 d일 (E)', 'ko')` 대신 직접 만든다. 요일 이름을 로케일에서
/// 가져오려면 `initializeDateFormatting`이 선행돼야 하고, 초기화 여부에 따라
/// 테스트가 달라진다. 월 헤더가 연·월을 이미 갖고 있어 여기서는 반복하지 않는다.
String formatDayLabel(DateTime date) {
  final weekday = _weekdayLabels[date.weekday - 1];
  return '${date.month}월 ${date.day}일 ($weekday)';
}

/// 한 방향만 모아 최신순으로 나열한다.
///
/// 스크롤이 곧 시간축이 되도록 같은 방향 사진만 남기고, 각 사진에 직전 사진과의
/// 간격을 붙인다. 경과일은 [buildTimelineRows]와 달리 라벨을 구분하지 않고
/// 걸러진 목록 안에서만 센다 — 호출부가 이미 대상을 좁혀 놓는다.
List<DirectionRow> collectByDirection(
  List<RecordWithPhotos> entries,
  BodyDirection direction,
) {
  final rows = <DirectionRow>[];
  final matched = <({PhotoRecord record, BodyPhoto photo})>[];

  for (final entry in entries) {
    for (final photo in entry.orderedPhotos) {
      if (photo.direction != direction) continue;
      matched.add((record: entry.record, photo: photo));
      // 한 기록에 같은 방향이 여러 장이면 첫 장만 대표로 쓴다.
      break;
    }
  }

  for (var i = 0; i < matched.length; i++) {
    final current = matched[i];
    final older = i + 1 < matched.length ? matched[i + 1] : null;
    rows.add(
      DirectionRow(
        record: current.record,
        photo: current.photo,
        daysSincePrevious: older == null
            ? null
            : daysBetween(older.record.shotAt, current.record.shotAt),
      ),
    );
  }

  return rows;
}

/// 타임라인에 실제로 존재하는 방향만 필터 후보로 준다.
///
/// 사진이 한 장도 없는 방향을 칩으로 내보이면 눌러도 빈 화면이 나온다.
List<BodyDirection> availableDirections(List<RecordWithPhotos> entries) {
  final present = <BodyDirection>{};
  for (final entry in entries) {
    for (final photo in entry.photos) {
      present.add(photo.direction);
    }
  }
  return BodyDirection.values.where(present.contains).toList();
}

/// 비교 바로가기에 쓸 직전 기록.
///
/// 카드에서 비교로 직행할 때 이 기록을 '이후', 같은 대상의 직전 기록을 '이전'으로
/// 지정한다. 직전 기록이 없거나 겹치는 방향이 없으면 null을 돌려 호출부가
/// 수동 선택 화면으로 보내게 한다.
({RecordWithPhotos before, BodyDirection direction})? findCompareTarget(
  List<RecordWithPhotos> entries,
  String recordId,
) {
  final index = entries.indexWhere((e) => e.record.id == recordId);
  if (index < 0) return null;

  final current = entries[index];
  final label = normalizeLabel(current.record.label);
  final currentDirections = current.photos.map((p) => p.direction).toSet();
  if (currentDirections.isEmpty) return null;

  for (var j = index + 1; j < entries.length; j++) {
    final candidate = entries[j];
    if (normalizeLabel(candidate.record.label) != label) continue;

    // 양쪽에 모두 있는 방향 중 촬영 순서가 가장 앞선 것을 고른다.
    final shared = candidate.photos
        .map((p) => p.direction)
        .where(currentDirections.contains)
        .toList();
    if (shared.isEmpty) continue;
    shared.sort((a, b) => a.index.compareTo(b.index));
    return (before: candidate, direction: shared.first);
  }

  return null;
}
