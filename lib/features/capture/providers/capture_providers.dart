import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import '../camera/capture_camera_controller.dart';

/// id로 회원 정보를 조회한다. 잘못된 회원에게 등록되는 일을 막기 위해
/// 촬영/갤러리 등록 화면에서 회원 이름을 상시 표시할 때 사용한다.
final memberByIdProvider = FutureProvider.autoDispose.family<Member?, String>((
  ref,
  memberId,
) async {
  final repository = ref.watch(memberRepositoryProvider);
  return repository.getById(memberId);
});

/// 실제 카메라 컨트롤러 생성 팩토리. 테스트에서
/// `captureCameraControllerFactoryProvider.overrideWithValue(() => Fake...())`로
/// 교체해 실기기 카메라 없이 위젯을 검증한다.
final captureCameraControllerFactoryProvider =
    Provider<CaptureCameraController Function()>(
      (ref) => DeviceCaptureCameraController.new,
    );

typedef PreviousPhotoGuideKey = ({String memberId, BodyDirection direction});

/// 같은 회원·촬영 방향의 사진 중 가장 최근에 저장됐고 실제 파일도 남아 있는
/// 원본 경로를 찾는다. 최신 행의 파일이 유실됐으면 다음 사진을 확인한다.
///
/// 조회 실패는 [AsyncError], 정상적으로 사용할 사진이 없으면 null이다. 화면은
/// 두 경우 모두 카메라만 계속 사용할 수 있도록 가이드 없이 대체한다.
final previousPhotoGuidePathProvider = FutureProvider.autoDispose
    .family<String?, PreviousPhotoGuideKey>((ref, key) async {
      final photos = await ref
          .watch(bodyPhotoRepositoryProvider)
          .listByMemberDirection(key.memberId, key.direction);
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
