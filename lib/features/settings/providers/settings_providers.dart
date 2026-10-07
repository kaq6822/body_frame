import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/settings_save_queue.dart';
import '../services/app_settings_service.dart';
import '../services/storage_stats_service.dart';

/// settings 기능 전용 의존성 주입 지점.
///
/// core 리포지토리/서비스(사진·격자 등)는 `lib/core/providers.dart`의
/// provider를 그대로 재사용하고, 이 파일에서는 settings 기능이 추가한
/// 서비스(설정 영속화·저장 공간 통계)만 정의한다.

final appSettingsServiceProvider = Provider<AppSettingsService>((ref) {
  return AppSettingsServiceImpl(logger: ref.watch(appLoggerProvider));
});

final storageStatsServiceProvider = Provider<StorageStatsService>((ref) {
  return StorageStatsServiceImpl(
    database: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageServiceProvider),
  );
});

/// 앱 설정 저장 큐와 그 상태.
///
/// 저장은 순서를 보장하며 진행 중인 저장 동안 도착한 요청은 최신 값 하나로
/// 합친다. 빠르게 여러 설정을 바꾸어도 오래된 저장이 나중에 끝나 마지막 선택을
/// 덮어쓰는 일이 없다. 실패는 예외 대신 상태로 알린다.
final appSettingsSaveQueueProvider =
    StateNotifierProvider<SettingsSaveQueue<AppSettings>, SettingsSaveState>((
      ref,
    ) {
      return SettingsSaveQueue<AppSettings>(
        ref.watch(appSettingsServiceProvider).save,
      );
    });

/// 앱 설정(AppSettings) 상태. 화면들이 공유하는 단일 소스.
///
/// 저장은 [appSettingsSaveQueueProvider]를 통해 순서대로 진행된다. UI 값은
/// 저장 완료를 기다리지 않고 먼저 반영되므로 토글·드롭다운이 즉시 반응하고,
/// 저장이 끝난 뒤의 값도 마지막 선택과 일치한다. 실패는 저장 상태로 따로 알린다.
class AppSettingsController extends AsyncNotifier<AppSettings> {
  SettingsSaveQueue<AppSettings> get _saves =>
      ref.read(appSettingsSaveQueueProvider.notifier);

  @override
  Future<AppSettings> build() {
    return ref.watch(appSettingsServiceProvider).load();
  }

  /// 값은 저장 완료를 기다리지 않고 먼저 반영되므로 토글·드롭다운이 즉시 반응한다.
  ///
  /// 반환값은 저장의 결과다. 저장은 예외 대신 [SettingsSaveState]로 알리므로
  /// 호출부는 `result.isFailure`로 실패를 판정하고 재시도를 노출할 수 있다.
  /// 저장 도중 더 최신 요청이 들어오면 그 값이 대신 저장되므로, 여기 돌아오는
  /// 시점의 영속 값은 사용자의 마지막 선택과 일치한다.
  Future<SettingsSaveState> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final current = state.valueOrNull ?? AppSettings.defaults;
    final next = updater(current);
    state = AsyncValue.data(next);
    return _saves.save(next);
  }

  /// 마지막 저장 요청(실패한 경우)을 다시 시도한다.
  Future<void> retrySave() => _saves.retry();
}

final appSettingsControllerProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// 저장 공간 사용량(screen.settings.storage).
final storageUsageProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(storageStatsServiceProvider).collect();
});
