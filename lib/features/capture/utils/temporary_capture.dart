import 'dart:io';

import 'package:body_frame/core/services/app_logger.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';

/// 카메라가 만든 임시 촬영 파일을 최선 노력으로 지운다.
///
/// 카메라 플러그인은 캐시/임시 디렉터리에 파일을 남기고 경로만 돌려주므로,
/// 그 컷을 버리는 쪽이 직접 지워야 한다. 저장할 때 관리 저장소로 복사한 뒤에도
/// 원본 임시 파일은 그대로 남는다.
///
/// **관리 저장소 안의 파일은 절대 지우지 않는다.** 그쪽은 사용자의 원본이다.
/// 삭제 실패는 남은 파일이 캐시에 있을 뿐이라 화면 흐름을 막지 않는다.
Future<void> deleteTemporaryCaptureBestEffort(
  String path, {
  required PhotoStorageService storage,
  required AppLogger logger,
}) async {
  try {
    final stored = await storage.toStoredPath(path);
    if (stored.startsWith('${PhotoStorageServiceImpl.rootDirName}/')) {
      return;
    }
  } catch (_) {
    // 카메라가 반환하는 cache/tmp 경로는 변환에 실패하는 것이 정상이다.
  }
  try {
    final source = File(path);
    if (await source.exists()) {
      await source.delete();
    }
  } catch (_) {
    logger.warn('capture.source.cleanup.failure');
  }
}
