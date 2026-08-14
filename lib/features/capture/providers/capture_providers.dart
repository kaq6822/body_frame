import 'dart:io';

// 이 앱에도 같은 이름의 설정 모델(core/models/app_settings.dart)이 있어 구분한다.
import 'package:app_settings/app_settings.dart' as platform_settings;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import '../camera/capture_camera_controller.dart';

/// 실제 카메라 컨트롤러 생성 팩토리. 테스트에서
/// `captureCameraControllerFactoryProvider.overrideWithValue(() => Fake...())`로
/// 교체해 실기기 카메라 없이 위젯을 검증한다.
final captureCameraControllerFactoryProvider =
    Provider<CaptureCameraController Function()>(
      (ref) => DeviceCaptureCameraController.new,
    );

/// 이 앱의 시스템 설정 화면을 여는 플랫폼 경계.
///
/// 권한을 거부한 사용자가 설정 앱을 직접 헤매지 않게 앱 정보 화면으로 바로
/// 보낸다. 플러그인 채널을 타므로 위젯 테스트에서는 이 provider를 교체해
/// "눌렀을 때 열기를 요청하는지"만 확인한다.
final openAppSettingsProvider = Provider<Future<void> Function()>(
  (ref) => platform_settings.AppSettings.openAppSettings,
);

/// 같은 촬영 방향의 사진 중 가장 최근에 저장됐고 실제 파일도 남아 있는
/// 원본 경로를 찾는다. 최신 행의 파일이 유실됐으면 다음 사진을 확인한다.
///
/// 조회 실패는 [AsyncError], 정상적으로 사용할 사진이 없으면 null이다. 화면은
/// 두 경우 모두 카메라만 계속 사용할 수 있도록 가이드 없이 대체한다.
final previousPhotoGuidePathProvider = FutureProvider.autoDispose
    .family<String?, BodyDirection>((ref, direction) async {
      final photos = await ref
          .watch(bodyPhotoRepositoryProvider)
          .listByDirection(direction);
      for (final photo in photos) {
        try {
          final file = File(photo.filePath);
          if (await file.exists() && await file.length() > 0) {
            return photo.filePath;
          }
        } on FileSystemException {
          // 저장소 행만 남은 파일은 건너뛰고 다음 최신 사진을 확인한다.
        }
      }
      return null;
    });

/// 격자 설정 로드/저장/초기화 상태.
///
/// [GridSettingsService]로 shared_preferences에 영속화한다. 화면은 이
/// provider만 watch하면 되고, 로드/저장 실패는 [AsyncValue.error]로 노출된다.
class GridSettingsController extends StateNotifier<AsyncValue<GridSettings>> {
  final GridSettingsService _service;

  GridSettingsController(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final settings = await _service.load();
      state = AsyncValue.data(settings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// 로드 실패 시 재시도.
  Future<void> retry() => _load();

  Future<void> update(
    GridSettings Function(GridSettings current) updater,
  ) async {
    final current = state.value ?? GridSettings.defaults;
    final next = updater(current);
    state = AsyncValue.data(next);
    await _service.save(next);
  }

  Future<void> reset() async {
    await _service.reset();
    state = const AsyncValue.data(GridSettings.defaults);
  }
}

final gridSettingsControllerProvider =
    StateNotifierProvider.autoDispose<
      GridSettingsController,
      AsyncValue<GridSettings>
    >((ref) => GridSettingsController(ref.watch(gridSettingsServiceProvider)));
