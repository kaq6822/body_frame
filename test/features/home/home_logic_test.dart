import 'package:bodymark/features/home/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_fixtures.dart';

void main() {
  group('오늘 예상 회원', () {
    test('지난 28일 같은 요일 회원을 대표 시각순으로, 오늘 기록한 회원은 뒤로 보낸다', () {
      final members = [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) member(id),
      ];
      final result = expectedMembersToday(
        members: members,
        now: now,
        lessons: [
          // a: 가장 최근 화요일(11.10) 15:00가 대표 시각이다.
          lesson('a', DateTime(2026, 11, 10, 15)),
          lesson('a', DateTime(2026, 11, 3, 18)),
          lesson('b', DateTime(2026, 11, 10, 9, 30)),
          // c: 정확히 28일 전 화요일은 포함한다.
          lesson('c', DateTime(2026, 10, 20, 12)),
          // d: 35일 전은 기간 밖이다.
          lesson('d', DateTime(2026, 10, 13, 12)),
          // e: 다른 요일(월)은 고르지 않는다.
          lesson('e', DateTime(2026, 11, 16, 11)),
          // f: 오늘 이미 기록했다.
          lesson('f', DateTime(2026, 11, 10, 8)),
          lesson('f', DateTime(2026, 11, 17, 7)),
          // 회원 미연결·목록에 없는 회원은 제외한다.
          lesson(null, DateTime(2026, 11, 10, 10)),
          lesson('ghost', DateTime(2026, 11, 10, 10)),
        ],
      );
      expect(result.map((e) => e.member.id), ['b', 'c', 'a', 'f']);
      expect(result.first.lastSameWeekday, DateTime(2026, 11, 10, 9, 30));
      expect(result[2].lastSameWeekday, DateTime(2026, 11, 10, 15));
      expect(result.map((e) => e.recordedToday), [false, false, false, true]);
    });

    test('오늘 기록만 있고 지난 같은 요일 기록이 없으면 고르지 않는다', () {
      final result = expectedMembersToday(
        members: [member('a')],
        now: now,
        lessons: [lesson('a', DateTime(2026, 11, 17, 9))],
      );
      expect(result, isEmpty);
    });

    test('같은 시각이면 이름순이다', () {
      final result = expectedMembersToday(
        members: [
          member('x', name: '하나'),
          member('y', name: '가나'),
        ],
        now: now,
        lessons: [
          lesson('x', DateTime(2026, 11, 10, 10)),
          lesson('y', DateTime(2026, 11, 3, 10)),
        ],
      );
      expect(result.map((e) => e.member.name), ['가나', '하나']);
    });
  });

  group('이번 주', () {
    test('월요일 0시부터 일요일 끝까지 회원 레슨만 센다', () {
      final lessons = [
        lesson('a', DateTime(2026, 11, 15, 23, 59)), // 지난주 일요일
        lesson('a', DateTime(2026, 11, 16), phases: ['before', 'after']),
        lesson('b', DateTime(2026, 11, 22, 23, 59), phases: ['regular']),
        lesson('b', DateTime(2026, 11, 23)), // 다음 주 월요일
        lesson(null, DateTime(2026, 11, 17), phases: ['regular']),
        // 목록에 없는(삭제된) 회원의 레슨은 다른 섹션처럼 세지 않는다.
        lesson('gone', DateTime(2026, 11, 17), phases: ['regular']),
      ];
      final stats = weekStats(
        members: [member('a'), member('b')],
        lessons: lessons,
        now: now,
      );
      expect(stats.weekStart, DateTime(2026, 11, 16));
      expect(stats.lessons, 2);
      expect(stats.photoRecords, 3);
      expect(stats.members, 2);
    });

    test('일요일에도 그 주 월요일부터 센다', () {
      final sunday = DateTime(2026, 11, 22, 21);
      final stats = weekStats(
        members: [member('a')],
        lessons: [lesson('a', DateTime(2026, 11, 16, 9))],
        now: sunday,
      );
      expect(stats.weekStart, DateTime(2026, 11, 16));
      expect(stats.lessons, 1);
    });

    test('월요일 이른 시각에는 바로 그날부터 센다', () {
      final stats = weekStats(
        members: [member('a')],
        lessons: [lesson('a', DateTime(2026, 11, 15, 22))],
        now: DateTime(2026, 11, 16, 0, 5),
      );
      expect(stats.weekStart, DateTime(2026, 11, 16));
      expect(stats.lessons, 0);
    });
  });

  group('한동안 기록이 없는 회원', () {
    test('14일 이상 지난 회원을 오래된 순으로, 등록 14일 이상인 레슨 없는 회원은 뒤에 둔다', () {
      final result = idleMembers(
        members: [
          member('recent'),
          member('edge'),
          member('old'),
          // 등록 16일째·14일째는 포함, 13일째는 방금 등록한 회원이라 제외한다.
          member('new', createdAt: DateTime(2026, 11, 1)),
          member('fresh14', createdAt: DateTime(2026, 11, 3, 23)),
          member('fresh13', createdAt: DateTime(2026, 11, 4)),
          member('never', createdAt: DateTime(2026, 3, 1)),
        ],
        now: now,
        lessons: [
          lesson('recent', DateTime(2026, 11, 4, 23)), // 13일
          lesson('edge', DateTime(2026, 11, 3, 23)), // 14일
          lesson('old', DateTime(2026, 10, 1)),
          lesson('old', DateTime(2026, 9, 1)),
        ],
      );
      expect(result.map((e) => e.member.id), [
        'old',
        'edge',
        'never',
        'new',
        'fresh14',
      ]);
      expect(result.map((e) => e.days), [47, 14, null, null, null]);
    });
  });

  test('최근 레슨은 회원 레슨 중 실제 레슨 일시가 가장 늦은 것이다', () {
    final latest = latestMemberLesson(
      members: [member('a'), member('b')],
      now: now,
      lessons: [
        // 지금 이후로 적힌 레슨은 "방금 한 레슨"이 아니다.
        lesson('a', DateTime(2026, 11, 20), id: 'future'),
        lesson('a', DateTime(2026, 11, 10), id: 'old'),
        lesson('b', DateTime(2026, 11, 16), id: 'new'),
        lesson(null, DateTime(2026, 11, 17), id: 'unlinked'),
        lesson('gone', DateTime(2026, 11, 17), id: 'deleted'),
      ],
    );
    expect(latest?.record.id, 'new');
    expect(
      latestMemberLesson(members: const [], lessons: const [], now: now),
      isNull,
    );
  });

  test('사진 기록 수는 레슨 × 구분이다', () {
    expect(
      photoRecordCount([
        lesson('a', now, phases: ['before', 'before', 'after']),
        lesson('a', now, phases: ['regular']),
        lesson('a', now),
      ]),
      3,
    );
  });

  test('28일 창은 달력 날짜로 계산해 서머타임이 있어도 같은 요일 경계를 지킨다', () {
    // 시각이 자정 직후여도 28일 전 같은 요일의 늦은 레슨까지 포함한다.
    final early = DateTime(2026, 11, 17, 0, 10);
    final result = expectedMembersToday(
      members: [member('a'), member('b')],
      now: early,
      lessons: [
        lesson('a', DateTime(2026, 10, 20, 23, 50)),
        lesson('b', DateTime(2026, 10, 13, 23, 50)),
      ],
    );
    expect(result.map((e) => e.member.id), ['a']);
  });

  test('앞날로 적힌 레슨이 있는 회원은 idle이 아니고 경과일은 음수가 되지 않는다', () {
    final result = idleMembers(
      members: [member('future'), member('past')],
      now: now,
      lessons: [
        lesson('future', DateTime(2026, 9, 1)),
        lesson('future', DateTime(2026, 11, 24)),
        lesson('past', DateTime(2026, 9, 1)),
      ],
    );
    expect(result.map((e) => e.member.id), ['past']);
    expect(result.every((e) => (e.days ?? 0) >= 0), isTrue);
  });
}
