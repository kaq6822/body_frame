import 'package:body_frame/core/photo_frame.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kPhotoFrameAspect', () {
    test('세로로 긴 3:4다', () {
      // 가로 ÷ 세로 규약이므로 1보다 작아야 세로로 길다.
      expect(kPhotoFrameAspect, 0.75);
      expect(kPhotoFrameAspect, lessThan(1));
    });
  });

  group('previewAspectFor', () {
    test('세로 화면에서는 가로 기준 센서 비율을 뒤집는다', () {
      // 16:9 센서(1.78) → 세로 9:16(0.5625)
      expect(
        previewAspectFor(
          sensorAspect: 16 / 9,
          orientation: Orientation.portrait,
        ),
        closeTo(9 / 16, 1e-9),
      );
      // 4:3 센서(1.33) → 세로 3:4(0.75)
      expect(
        previewAspectFor(
          sensorAspect: 4 / 3,
          orientation: Orientation.portrait,
        ),
        closeTo(3 / 4, 1e-9),
      );
    });

    test('가로 화면에서는 센서 비율을 그대로 쓴다', () {
      expect(
        previewAspectFor(
          sensorAspect: 16 / 9,
          orientation: Orientation.landscape,
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('정사각 센서는 방향과 무관하게 1이다', () {
      expect(
        previewAspectFor(sensorAspect: 1, orientation: Orientation.portrait),
        1,
      );
      expect(
        previewAspectFor(sensorAspect: 1, orientation: Orientation.landscape),
        1,
      );
    });

    test('이미 세로 기준으로 들어와도 같은 결과를 준다', () {
      // 플랫폼이 0.5625(9:16)로 보고하더라도 세로 미리보기 비율은 그대로 0.5625다.
      expect(
        previewAspectFor(
          sensorAspect: 9 / 16,
          orientation: Orientation.portrait,
        ),
        closeTo(9 / 16, 1e-9),
      );
      expect(
        previewAspectFor(
          sensorAspect: 9 / 16,
          orientation: Orientation.landscape,
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('유효하지 않은 값은 4:3 센서로 가정한다', () {
      for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          previewAspectFor(
            sensorAspect: invalid,
            orientation: Orientation.portrait,
          ),
          closeTo(3 / 4, 1e-9),
          reason: '$invalid 를 안전한 기본값으로 처리해야 합니다.',
        );
      }
    });
  });

  group('fitPhotoFrame', () {
    test('세로로 넉넉하면 폭을 가득 채운다', () {
      final size = fitPhotoFrame(
        const BoxConstraints(maxWidth: 300, maxHeight: 1000),
      );

      expect(size.width, 300);
      expect(size.height, 400);
    });

    test('세로가 좁으면 높이에 맞춰 줄여 넘치지 않는다', () {
      final size = fitPhotoFrame(
        const BoxConstraints(maxWidth: 300, maxHeight: 200),
      );

      expect(size.height, 200);
      expect(size.width, 150);
      expect(size.width, lessThanOrEqualTo(300));
    });

    test('어떤 제약에서도 3:4 비율을 유지한다', () {
      const cases = [
        BoxConstraints(maxWidth: 393, maxHeight: 873),
        BoxConstraints(maxWidth: 800, maxHeight: 600),
        BoxConstraints(maxWidth: 100, maxHeight: 100),
      ];
      for (final constraints in cases) {
        final size = fitPhotoFrame(constraints);
        expect(
          size.width / size.height,
          closeTo(kPhotoFrameAspect, 1e-9),
          reason: '$constraints 에서 비율이 어긋났습니다.',
        );
      }
    });

    test('폭이 무한하면 높이를 기준으로 정한다', () {
      final size = fitPhotoFrame(const BoxConstraints(maxHeight: 400));

      expect(size.height, 400);
      expect(size.width, 300);
    });

    test('양쪽이 모두 무한하면 그리지 않는다', () {
      expect(fitPhotoFrame(const BoxConstraints()), Size.zero);
    });
  });
}
