import 'package:body_frame/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';

/// 촬영일 계산 공용 함수 테스트.
///
/// 화면마다 날짜 공식을 따로 두면 서머타임 경계에서 값이 어긋난다. 이 테스트는
/// 타임라인 경과일과 비교 기간이 같은 규칙을 쓰는 근거이며, 기기 시간대와
/// 무관하게(`TZ=America/New_York flutter test`) 통과해야 한다.
void main() {
  group('dateOnly', () {
    test('시각 성분을 버리고 날짜만 남긴다', () {
      expect(dateOnly(DateTime(2026, 3, 8, 23, 59, 59)), DateTime(2026, 3, 8));
    });
  });

  group('daysBetween', () {
    test('같은 날은 시각이 달라도 0일이다', () {
      expect(
        daysBetween(DateTime(2026, 3, 8, 1, 30), DateTime(2026, 3, 8, 23, 30)),
        0,
      );
    });

    test('7일 뒤는 7일이다', () {
      expect(daysBetween(DateTime(2026, 1, 10), DateTime(2026, 1, 17)), 7);
    });

    test('인자를 바꾸어도 같은 기간을 돌려준다', () {
      // 비교 기간은 이전/이후를 교환할 수 있다. 부호만 바뀌면 안 되고 같은
      // 크기가 나와야 화면 문구가 흔들리지 않는다.
      final older = DateTime(2026, 1, 10, 21);
      final newer = DateTime(2026, 3, 20, 5);

      expect(daysBetween(newer, older).abs(), daysBetween(older, newer).abs());
    });

    test('월 경계와 연 경계를 정확히 센다', () {
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 1)), 1);
      expect(daysBetween(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 1);
      // 윤년이 낀 해에도 하루씩 센다.
      expect(daysBetween(DateTime(2024, 2, 28), DateTime(2024, 3, 1)), 2);
    });

    test('서머타임이 낀 구간에서도 달력 날짜 차이를 그대로 센다', () {
      final start = DateTime(2026, 2, 20);
      for (var offset = 1; offset <= 400; offset++) {
        final later = DateTime(start.year, start.month, start.day + offset);
        expect(
          daysBetween(start, later),
          offset,
          reason: '$offset일 뒤 날짜의 경과일이 어긋난다: $later',
        );
      }
    });
  });
}
