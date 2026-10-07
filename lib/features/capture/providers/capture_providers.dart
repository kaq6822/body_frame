import 'dart:async';
import 'dart:io';

// 이 앱에도 같은 이름의 설정 모델(core/models/app_settings.dart)이 있어 구분한다.
import 'package:app_settings/app_settings.dart' as platform_settings;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:body_frame/core/services/settings_save_queue.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:body_frame/features/records/records_timeline_logic.dart';
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

/// 같은 촬영 방향의 **본인 기록** 사진 중 가장 최근에 저장됐고 실제 파일도 남아
/// 있는 원본 경로를 찾는다. 최신 행의 파일이 유실됐으면 더 오래된 본인 사진을
/// 확인한다.
///
/// 가이드는 다음 촬영의 정렬 기준이므로 다른 사람이 찍은 기록을 기준으로 제시하면
/// 자세를 비교하는 의미가 어긋난다. 라벨이 붙은 기록은 후보에서 제외하고, 본인
/// 사진이 하나도 없으면 null을 돌려 가이드 없이 촬영만 계속되게 한다.
///
/// 조회 실패는 [AsyncError], 정상적으로 사용할 사진이 없으면 null이다. 화면은
/// 두 경우 모두 카메라만 계속 사용할 수 있도록 가이드 없이 대체한다.
final previousPhotoGuidePathProvider = FutureProvider.autoDispose
    .family<String?, BodyDirection>((ref, direction) async {
      // 촬영 화면은 앱의 루트라 저장·삭제·교체를 오가는 동안 계속 살아 있다.
      // [bodyPhotoRepositoryProvider]는 값이 바뀌지 않는 Provider여서 그것만
      // 지켜보면 캐시된 옛 경로가 그대로 남는다. 기록이 바뀌었다는 신호를 주는
      // [timelineProvider]를 함께 지켜봐 방금 찍은 사진이 가이드에 반영되게 한다.
      // 값이 아니라 무효화 신호만 쓰므로 타임라인 조회 실패는 가이드에 옮기지
      // 않는다 — 아래 조회는 사진과 기록을 각각 독립적으로 수행한다.
      ref.watch(timelineProvider);
      final photosFuture = ref
          .watch(bodyPhotoRepositoryProvider)
          .listByDirection(direction);
      final recordsFuture = ref.watch(photoRecordRepositoryProvider).listAll();
      final photos = await photosFuture;
      // 사진 행만으로는 대상 라벨을 알 수 없어 기록 목록에서 함께 읽는다.
      final records = await recordsFuture;
      final labelByRecordId = {
        for (final record in records) record.id: normalizeLabel(record.label),
      };
      for (final photo in photos) {
        // 다른 사람 기록은 정렬 기준으로 삼지 않는다.
        if (labelByRecordId[photo.recordId] != null) continue;
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

/// 격자 설정 저장 큐와 그 상태.
///
/// 저장은 순서를 보장하며 최신 요청으로 합쳐진다(앞뒤 순서가 뒤집히거나 드래그
/// 중 모든 중간값이 기록되지 않는다). 실패는 예외로 던지지 않고 상태로 알린다.
/// 컨트롤러가 autoDispose여도 저장은 끝까지 진행되도록 이 provider는 남겨 둔다.
final gridSettingsSaveQueueProvider =
    StateNotifierProvider<SettingsSaveQueue<GridSettings>, SettingsSaveState>((
      ref,
    ) {
      final service = ref.watch(gridSettingsServiceProvider);
      return SettingsSaveQueue<GridSettings>(
        service.save,
        reset: service.reset,
      );
    });

/// 격자 설정 로드/저장/초기화 상태.
///
/// [GridSettingsService]로 shared_preferences에 영속화한다. 화면은 이
/// provider만 watch하면 되고, 로드 실패는 [AsyncValue.error]로 노출된다.
///
/// 저장 실패는 [gridSettingsSaveQueueProvider]로 따로 알린다. 저장 중이거나
/// 실패해도 [state]는 마지막 선택값을 유지하므로 슬라이더 미리보기와 카메라
/// 화면이 저장 결과에 흔들리지 않는다.
class GridSettingsController extends StateNotifier<AsyncValue<GridSettings>> {
  final GridSettingsService _service;
  final SettingsSaveQueue<GridSettings> _saves;

  GridSettingsController(this._service, this._saves)
    : super(const AsyncValue.loading()) {
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

  /// 값을 먼저 반영한 뒤 저장한다.
  ///
  /// 슬라이더를 움직이면 미리보기가 즉시 따라와야 하므로 값 갱신과 저장을 나눈다.
  Future<void> update(
    GridSettings Function(GridSettings current) updater,
  ) async {
    final current = state.value ?? GridSettings.defaults;
    final next = updater(current);
    state = AsyncValue.data(next);
    await _saves.save(next);
  }

  /// 마지막 저장 요청(실패한 경우)을 다시 시도한다.
  Future<void> retrySave() => _saves.retry();

  Future<void> reset() async {
    state = const AsyncValue.data(GridSettings.defaults);
    await _saves.resetToDefault();
  }
}

final gridSettingsControllerProvider =
    StateNotifierProvider.autoDispose<
      GridSettingsController,
      AsyncValue<GridSettings>
    >(
      (ref) => GridSettingsController(
        ref.watch(gridSettingsServiceProvider),
        ref.read(gridSettingsSaveQueueProvider.notifier),
      ),
    );
