import 'package:body_frame/features/capture/camera/capture_camera_controller.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

/// 해상도 프리셋 폴백 선택 로직 검증.
///
/// 실기기 카메라 없이 확인할 수 있도록 초기화 시도를 콜백으로 분리해 두었다.
/// 홈이 카메라인 구조에서 초기화 실패는 앱이 열리지 않는 것과 같으므로, 높은
/// 프리셋이 막히는 기기에서도 반드시 낮은 쪽으로 내려가야 한다.
void main() {
  group('kResolutionFallbackChain', () {
    test('높은 해상도부터 내려가는 순서다', () {
      expect(kResolutionFallbackChain, [
        ResolutionPreset.max,
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]);
    });

    test('마지막은 대부분의 기기가 지원하는 값이다', () {
      // medium(480p)보다 낮추면 체형 기록으로 쓸 수 없다. 여기가 하한선이다.
      expect(kResolutionFallbackChain.last, ResolutionPreset.medium);
    });
  });

  group('selectWorkingPreset', () {
    test('첫 프리셋이 성공하면 나머지는 시도하지 않는다', () async {
      final tried = <ResolutionPreset>[];

      final selected = await selectWorkingPreset(
        presets: kResolutionFallbackChain,
        attempt: (preset) async => tried.add(preset),
      );

      expect(selected, ResolutionPreset.max);
      expect(tried, [ResolutionPreset.max]);
    });

    test('앞선 프리셋이 실패하면 다음으로 내려가 성공한 값을 돌려준다', () async {
      final tried = <ResolutionPreset>[];

      final selected = await selectWorkingPreset(
        presets: kResolutionFallbackChain,
        attempt: (preset) async {
          tried.add(preset);
          // max·veryHigh를 지원하지 않는 기기를 흉내낸다.
          if (preset != ResolutionPreset.high) {
            throw CameraException('resolution', '지원하지 않는 해상도(테스트)');
          }
        },
      );

      expect(selected, ResolutionPreset.high);
      expect(tried, [
        ResolutionPreset.max,
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
      ]);
    });

    test('실패한 프리셋마다 onFailure를 알린다', () async {
      final failed = <ResolutionPreset>[];

      await selectWorkingPreset(
        presets: kResolutionFallbackChain,
        attempt: (preset) async {
          if (preset != ResolutionPreset.medium) {
            throw StateError('실패(테스트)');
          }
        },
        onFailure: (preset, error) => failed.add(preset),
      );

      expect(failed, [
        ResolutionPreset.max,
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
      ]);
    });

    test('전부 실패하면 마지막 예외를 그대로 던진다', () async {
      // 호출부가 기존과 같은 방식으로 "카메라를 쓸 수 없다"를 다뤄야 한다.
      await expectLater(
        selectWorkingPreset(
          presets: kResolutionFallbackChain,
          attempt: (preset) async {
            throw CameraException('$preset', '마지막 실패(테스트)');
          },
        ),
        throwsA(
          isA<CameraException>().having(
            (e) => e.code,
            'code',
            '${ResolutionPreset.medium}',
          ),
        ),
      );
    });

    test('프리셋이 하나뿐이면 그것만 시도한다', () async {
      final tried = <ResolutionPreset>[];

      final selected = await selectWorkingPreset(
        presets: const [ResolutionPreset.medium],
        attempt: (preset) async => tried.add(preset),
      );

      expect(selected, ResolutionPreset.medium);
      expect(tried, [ResolutionPreset.medium]);
    });
  });
}
