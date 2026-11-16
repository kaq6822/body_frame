import '../members/member.dart';
import '../records/providers/records_providers.dart';

/// 홈 화면 요약 계산. 예약 기능이 없으므로 "다음 회원"은 지난 기록에서
/// 추정한다. 모두 순수 함수라 현재 시각([now])을 인자로 받는다.

/// 추정에 쓰는 기간. 오늘을 빼고 지난 28일(같은 요일 4번)을 본다.
const expectedWindowDays = 28;

/// 마지막 레슨 뒤 이 일수 이상 지나면 "한동안 기록이 없는 회원"으로 본다.
const idleThresholdDays = 14;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// 달력 기준 일수 차이. 서머타임과 무관하게 날짜만 비교한다.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// 사진 기록 수. 한 레슨의 수업 전·후 사진은 두 기록으로 센다(레슨 × 구분).
int photoRecordCount(Iterable<RecordWithPhotos> lessons) =>
    lessons.fold(0, (n, x) => n + x.photos.map((p) => p.phase).toSet().length);

class ExpectedMember {
  final Member member;

  /// 같은 요일 레슨 중 가장 최근 것의 일시. 시각을 "보통 몇 시"로 쓴다.
  final DateTime lastSameWeekday;

  /// 오늘 이미 레슨을 기록했는지.
  final bool recordedToday;

  const ExpectedMember({
    required this.member,
    required this.lastSameWeekday,
    required this.recordedToday,
  });
}

/// 오늘 올 것으로 보이는 회원.
///
/// 오늘을 뺀 최근 [expectedWindowDays]일 안에서 오늘과 같은 요일에 레슨이 있던
/// 회원을 고른다. 회원마다 그 요일 레슨 중 가장 최근 것의 시각을 대표로 쓰고,
/// 아직 기록하지 않은 회원을 시각순으로 앞에, 오늘 기록한 회원을 뒤에 둔다.
List<ExpectedMember> expectedMembersToday({
  required List<Member> members,
  required List<RecordWithPhotos> lessons,
  required DateTime now,
}) {
  final today = _day(now);
  // 서머타임과 무관하게 달력 날짜로 뺀다(weekStats와 같은 방식).
  final windowStart = DateTime(
    today.year,
    today.month,
    today.day - expectedWindowDays,
  );
  final byId = {for (final m in members) m.id: m};
  final latest = <String, DateTime>{};
  final recordedToday = <String>{};
  for (final x in lessons) {
    final id = x.record.memberId;
    if (id == null || !byId.containsKey(id)) continue;
    final at = x.record.shotAt;
    final day = _day(at);
    if (day == today) {
      recordedToday.add(id);
      continue;
    }
    if (day.isBefore(windowStart) ||
        !day.isBefore(today) ||
        at.weekday != now.weekday) {
      continue;
    }
    final current = latest[id];
    if (current == null || at.isAfter(current)) latest[id] = at;
  }
  int minutes(DateTime d) => d.hour * 60 + d.minute;
  final result = [
    for (final e in latest.entries)
      ExpectedMember(
        member: byId[e.key]!,
        lastSameWeekday: e.value,
        recordedToday: recordedToday.contains(e.key),
      ),
  ];
  result.sort((a, b) {
    if (a.recordedToday != b.recordedToday) return a.recordedToday ? 1 : -1;
    final t = minutes(a.lastSameWeekday).compareTo(minutes(b.lastSameWeekday));
    return t != 0 ? t : a.member.name.compareTo(b.member.name);
  });
  return result;
}

class WeekStats {
  final DateTime weekStart;
  final int lessons;
  final int photoRecords;
  final int members;
  const WeekStats({
    required this.weekStart,
    required this.lessons,
    required this.photoRecords,
    required this.members,
  });
}

/// 이번 주(월요일 0시 시작) 회원 레슨 집계. 다른 섹션과 같이 지금 있는
/// 회원([members])의 레슨만 센다(회원 미연결·삭제된 회원 기록 제외).
WeekStats weekStats({
  required List<Member> members,
  required List<RecordWithPhotos> lessons,
  required DateTime now,
}) {
  final ids = {for (final m in members) m.id};
  final today = _day(now);
  final start = DateTime(
    today.year,
    today.month,
    today.day - (now.weekday - 1),
  );
  final end = DateTime(start.year, start.month, start.day + 7);
  final inWeek = lessons
      .where(
        (x) =>
            ids.contains(x.record.memberId) &&
            !x.record.shotAt.isBefore(start) &&
            x.record.shotAt.isBefore(end),
      )
      .toList();
  return WeekStats(
    weekStart: start,
    lessons: inWeek.length,
    photoRecords: photoRecordCount(inWeek),
    members: inWeek.map((x) => x.record.memberId).toSet().length,
  );
}

class IdleMember {
  final Member member;

  /// 마지막 레슨 일시. 한 번도 없으면 null.
  final DateTime? lastLessonAt;

  /// 마지막 레슨 뒤 지난 일수. 한 번도 없으면 null.
  final int? days;

  const IdleMember({required this.member, this.lastLessonAt, this.days});
}

/// 마지막 레슨이 [idleThresholdDays]일 이상 지난 회원을 오래된 순으로 고른다.
/// 레슨이 한 번도 없는 회원은 등록 뒤 [idleThresholdDays]일 이상 지났을 때만
/// 그 뒤에 등록이 오래된 순으로 둔다.
List<IdleMember> idleMembers({
  required List<Member> members,
  required List<RecordWithPhotos> lessons,
  required DateTime now,
}) {
  final last = <String, DateTime>{};
  final upcoming = <String>{};
  for (final x in lessons) {
    final id = x.record.memberId;
    if (id == null) continue;
    // 지금 이후로 적힌 레슨이 있으면 이미 다음 레슨이 잡힌 회원이라 제외하고,
    // 경과일은 지난 레슨으로만 센다(음수가 되지 않게).
    if (x.record.shotAt.isAfter(now)) {
      upcoming.add(id);
      continue;
    }
    final current = last[id];
    if (current == null || x.record.shotAt.isAfter(current)) {
      last[id] = x.record.shotAt;
    }
  }
  final dated = <IdleMember>[];
  final never = <IdleMember>[];
  for (final m in members) {
    if (upcoming.contains(m.id)) continue;
    final at = last[m.id];
    if (at == null) {
      // 방금 등록한 회원은 "한동안 기록이 없다"고 보지 않는다.
      if (calendarDaysBetween(m.createdAt, now) >= idleThresholdDays) {
        never.add(IdleMember(member: m));
      }
      continue;
    }
    final days = calendarDaysBetween(at, now);
    if (days >= idleThresholdDays) {
      dated.add(IdleMember(member: m, lastLessonAt: at, days: days));
    }
  }
  dated.sort((a, b) {
    final c = a.lastLessonAt!.compareTo(b.lastLessonAt!);
    return c != 0 ? c : a.member.name.compareTo(b.member.name);
  });
  never.sort((a, b) {
    final c = a.member.createdAt.compareTo(b.member.createdAt);
    return c != 0 ? c : a.member.name.compareTo(b.member.name);
  });
  return [...dated, ...never];
}

/// 가장 최근 회원 레슨(실제 레슨 일시 기준). 지금 이후로 적힌 레슨은 "방금
/// 한 레슨"이 아니므로 제외한다. 없으면 null.
RecordWithPhotos? latestMemberLesson({
  required List<Member> members,
  required List<RecordWithPhotos> lessons,
  required DateTime now,
}) {
  final ids = {for (final m in members) m.id};
  RecordWithPhotos? best;
  for (final x in lessons) {
    if (!ids.contains(x.record.memberId)) continue;
    if (x.record.shotAt.isAfter(now)) continue;
    if (best == null ||
        x.record.shotAt.isAfter(best.record.shotAt) ||
        x.record.shotAt == best.record.shotAt &&
            x.record.createdAt.isAfter(best.record.createdAt)) {
      best = x;
    }
  }
  return best;
}
