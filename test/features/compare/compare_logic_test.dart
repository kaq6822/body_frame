import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/compare/compare_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BodyPhoto _photo(String id, BodyDirection direction, {String recordId = 'r'}) {
  return BodyPhoto(
    id: id,
    recordId: recordId,
    filePath: '/tmp/$id.jpg',
    direction: direction,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('commonDirections', () {
    test('양쪽에 모두 있는 방향만 BodyDirection 정의 순서로 반환한다', () {
      final before = [
        _photo('b1', BodyDirection.front),
        _photo('b2', BodyDirection.back),
      ];
      final after = [
        _photo('a1', BodyDirection.back),
        _photo('a2', BodyDirection.front),
        _photo('a3', BodyDirection.leftSide),
      ];

      final common = commonDirections(before, after);

      expect(common, [BodyDirection.front, BodyDirection.back]);
    });

    test('공통 방향이 없으면 빈 목록을 반환한다', () {
      final before = [_photo('b1', BodyDirection.front)];
      final after = [_photo('a1', BodyDirection.back)];

      expect(commonDirections(before, after), isEmpty);
    });

    test('한쪽이 비어 있으면 공통 방향이 없다', () {
      final before = <BodyPhoto>[];
      final after = [_photo('a1', BodyDirection.front)];

      expect(commonDirections(before, after), isEmpty);
    });
  });

  group('photoForDirection', () {
    test('일치하는 방향의 첫 사진을 반환한다', () {
      final photos = [
        _photo('p1', BodyDirection.front),
        _photo('p2', BodyDirection.leftSide),
      ];

      expect(photoForDirection(photos, BodyDirection.leftSide)?.id, 'p2');
    });

    test('일치하는 사진이 없으면 null을 반환한다', () {
      final photos = [_photo('p1', BodyDirection.front)];

      expect(photoForDirection(photos, BodyDirection.rightSide), isNull);
    });
  });

  group('directionAvailable', () {
    test('양쪽 모두 해당 방향 사진이 있어야 true', () {
      final before = [_photo('b1', BodyDirection.front)];
      final after = [_photo('a1', BodyDirection.front)];

      expect(directionAvailable(before, after, BodyDirection.front), isTrue);
    });

    test('한쪽에만 있으면 false', () {
      final before = [_photo('b1', BodyDirection.front)];
      final after = <BodyPhoto>[];

      expect(directionAvailable(before, after, BodyDirection.front), isFalse);
    });
  });
}
