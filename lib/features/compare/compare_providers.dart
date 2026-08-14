import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';

// allRecordsProvider/recordPhotosProvider는 home feature의 정의를 단일
// 출처로 재사용한다(중복 정의 시 invalidate가 서로 전파되지 않고 두 파일
// 동시 import에서 이름이 충돌한다).
export '../records/providers/records_providers.dart'
    show allRecordsProvider, recordPhotosProvider;

/// compare feature 전용 조회용 provider 모음.
///
/// core 리포지토리/서비스를 조합한다. 테스트에서는 core provider들을
/// `ProviderScope(overrides:)`로 Fake로 교체하면 이 provider들도 함께
/// 교체된 구현을 사용한다.

/// 단일 촬영 기록 조회(촬영일 표시용).
final recordByIdProvider = FutureProvider.family<PhotoRecord?, String>((
  ref,
  recordId,
) {
  return ref.watch(photoRecordRepositoryProvider).getById(recordId);
});

/// 전후 사진 비교 화면에 필요한 데이터 묶음.
class CompareViewBundle {
  final PhotoRecord beforeRecord;
  final PhotoRecord afterRecord;
  final BodyPhoto beforePhoto;
  final BodyPhoto afterPhoto;
  final GridSettings defaultGrid;

  const CompareViewBundle({
    required this.beforeRecord,
    required this.afterRecord,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.defaultGrid,
  });
}

/// [CompareViewBundle] 조회 키.
typedef CompareViewKey = ({String beforePhotoId, String afterPhotoId});

/// 사진/촬영 기록/기본 격자 설정을 한 번에 모아 전후 비교 화면에 공급한다.
final compareViewBundleProvider =
    FutureProvider.family<CompareViewBundle, CompareViewKey>((ref, key) async {
      final photos = ref.watch(bodyPhotoRepositoryProvider);
      final records = ref.watch(photoRecordRepositoryProvider);
      final grids = ref.watch(gridSettingsServiceProvider);

      final beforePhoto = await photos.getById(key.beforePhotoId);
      final afterPhoto = await photos.getById(key.afterPhotoId);
      if (beforePhoto == null || afterPhoto == null) {
        throw StateError('비교할 사진을 찾을 수 없습니다.');
      }
      if (beforePhoto.recordId == afterPhoto.recordId) {
        throw StateError('같은 촬영 기록의 사진끼리는 비교할 수 없습니다.');
      }

      final beforeRecord = await records.getById(beforePhoto.recordId);
      final afterRecord = await records.getById(afterPhoto.recordId);
      if (beforeRecord == null || afterRecord == null) {
        throw StateError('촬영 기록을 찾을 수 없습니다.');
      }

      final grid = await grids.load();

      return CompareViewBundle(
        beforeRecord: beforeRecord,
        afterRecord: afterRecord,
        beforePhoto: beforePhoto,
        afterPhoto: afterPhoto,
        defaultGrid: grid,
      );
    });
