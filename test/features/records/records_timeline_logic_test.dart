import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:body_frame/features/records/records_timeline_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 고정 날짜만 사용한다. 현재 시각에 의존하면 경과일 검증이 날마다 달라진다.
RecordWithPhotos _entry({
  required String id,
  required DateTime shotAt,
  String? label,
  List<BodyDirection> directions = const [BodyDirection.front],
}) {
  return RecordWithPhotos(
    record: PhotoRecord(
      id: id,
      shotAt: shotAt,
      label: label,
      createdAt: shotAt,
      updatedAt: shotAt,
    ),
    photos: [
      for (final direction in directions)
        BodyPhoto(
          id: '$id-${direction.key}',
          recordId: id,
          filePath: '/tmp/$id-${direction.key}.jpg',
          direction: direction,
          createdAt: shotAt,
        ),
    ],
  );
}

void main() {
  group('buildTimelineRows', () {
    test('경과일은 같은 대상 라벨끼리만 계산한다', () {
      // 본인(8/8) → 어머니(8/4) → 본인(8/1) 순서. 본인 기록 사이 간격은 7일이며
      // 중간에 끼인 다른 대상 기록에 영향받지 않아야 한다.
      final rows = buildTimelineRows([
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8)),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 4), label: '어머니'),
        _entry(id: 'c', shotAt: DateTime(2026, 8, 1)),
      ]);

      expect(rows[0].daysSincePrevious, 7);
      // 어머니 기록은 직전 어머니 기록이 없으므로 null.
      expect(rows[1].daysSincePrevious, isNull);
      expect(rows[2].daysSincePrevious, isNull);
    });

    test('공백만 있는 라벨은 본인 기록과 같은 대상으로 본다', () {
      final rows = buildTimelineRows([
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8), label: '   '),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 1)),
      ]);

      expect(rows[0].daysSincePrevious, 7);
    });

    test('월이 바뀌는 행에만 월 헤더가 붙는다', () {
      final rows = buildTimelineRows([
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8)),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 1)),
        _entry(id: 'c', shotAt: DateTime(2026, 7, 20)),
      ]);

      expect(rows[0].monthHeader, '2026년 8월');
      expect(rows[1].monthHeader, isNull);
      expect(rows[2].monthHeader, '2026년 7월');
    });

    test('해가 바뀌면 같은 월 번호여도 헤더가 새로 붙는다', () {
      final rows = buildTimelineRows([
        _entry(id: 'a', shotAt: DateTime(2026, 1, 5)),
        _entry(id: 'b', shotAt: DateTime(2025, 1, 5)),
      ]);

      expect(rows[0].monthHeader, '2026년 1월');
      expect(rows[1].monthHeader, '2025년 1월');
    });

    test('시각 성분이 달라도 경과일은 날짜 차이로 센다', () {
      final rows = buildTimelineRows([
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8, 23, 30)),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 7, 1, 0)),
      ]);

      expect(rows[0].daysSincePrevious, 1);
    });

    test('빈 목록은 빈 결과를 준다', () {
      expect(buildTimelineRows(const []), isEmpty);
    });
  });

  group('collectByDirection', () {
    test('해당 방향만 최신순으로 남기고 직전 사진과의 간격을 붙인다', () {
      final rows = collectByDirection([
        _entry(
          id: 'a',
          shotAt: DateTime(2026, 8, 8),
          directions: [BodyDirection.front, BodyDirection.back],
        ),
        // 정면이 없는 기록은 건너뛴다.
        _entry(
          id: 'b',
          shotAt: DateTime(2026, 8, 5),
          directions: [BodyDirection.back],
        ),
        _entry(id: 'c', shotAt: DateTime(2026, 8, 1)),
      ], BodyDirection.front);

      expect(rows.map((r) => r.record.id), ['a', 'c']);
      expect(rows[0].daysSincePrevious, 7);
      expect(rows[1].daysSincePrevious, isNull);
    });

    test('사진이 없는 방향은 빈 결과를 준다', () {
      final rows = collectByDirection([
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8)),
      ], BodyDirection.leftSide);

      expect(rows, isEmpty);
    });
  });

  group('availableDirections', () {
    test('실제로 사진이 있는 방향만 촬영 순서대로 준다', () {
      final directions = availableDirections([
        _entry(
          id: 'a',
          shotAt: DateTime(2026, 8, 8),
          directions: [BodyDirection.back, BodyDirection.front],
        ),
        _entry(
          id: 'b',
          shotAt: DateTime(2026, 8, 1),
          directions: [BodyDirection.front],
        ),
      ]);

      expect(directions, [BodyDirection.front, BodyDirection.back]);
    });
  });

  group('findCompareTarget', () {
    test('같은 대상의 직전 기록과 겹치는 방향을 고른다', () {
      final entries = [
        _entry(
          id: 'a',
          shotAt: DateTime(2026, 8, 8),
          directions: [BodyDirection.leftSide, BodyDirection.front],
        ),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 4), label: '어머니'),
        _entry(
          id: 'c',
          shotAt: DateTime(2026, 8, 1),
          directions: [BodyDirection.front, BodyDirection.leftSide],
        ),
      ];

      final target = findCompareTarget(entries, 'a');

      expect(target, isNotNull);
      expect(target!.before.record.id, 'c');
      // 겹치는 방향 중 촬영 순서가 가장 앞선 정면을 고른다.
      expect(target.direction, BodyDirection.front);
    });

    test('겹치는 방향이 없으면 더 과거 기록에서 찾는다', () {
      final entries = [
        _entry(
          id: 'a',
          shotAt: DateTime(2026, 8, 8),
          directions: [BodyDirection.back],
        ),
        _entry(
          id: 'b',
          shotAt: DateTime(2026, 8, 4),
          directions: [BodyDirection.front],
        ),
        _entry(
          id: 'c',
          shotAt: DateTime(2026, 8, 1),
          directions: [BodyDirection.back],
        ),
      ];

      final target = findCompareTarget(entries, 'a');

      expect(target!.before.record.id, 'c');
      expect(target.direction, BodyDirection.back);
    });

    test('직전 기록이 없으면 null을 준다', () {
      final entries = [_entry(id: 'a', shotAt: DateTime(2026, 8, 8))];

      expect(findCompareTarget(entries, 'a'), isNull);
    });

    test('다른 대상 기록만 있으면 null을 준다', () {
      final entries = [
        _entry(id: 'a', shotAt: DateTime(2026, 8, 8)),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 1), label: '어머니'),
      ];

      expect(findCompareTarget(entries, 'a'), isNull);
    });

    test('사진이 없는 기록은 비교 대상이 되지 않는다', () {
      final entries = [
        RecordWithPhotos(
          record: PhotoRecord(
            id: 'a',
            shotAt: DateTime(2026, 8, 8),
            createdAt: DateTime(2026, 8, 8),
            updatedAt: DateTime(2026, 8, 8),
          ),
          photos: const [],
        ),
        _entry(id: 'b', shotAt: DateTime(2026, 8, 1)),
      ];

      expect(findCompareTarget(entries, 'a'), isNull);
    });
  });
}
