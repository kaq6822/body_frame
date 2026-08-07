import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';

/// 전체 촬영 기록 목록(최신 촬영일 먼저).
final allRecordsProvider = FutureProvider.autoDispose<List<PhotoRecord>>((
  ref,
) async {
  return ref.watch(photoRecordRepositoryProvider).listAll();
});

/// 단일 촬영 기록 조회.
final recordProvider = FutureProvider.autoDispose
    .family<PhotoRecord?, String>((ref, recordId) async {
      return ref.watch(photoRecordRepositoryProvider).getById(recordId);
    });

/// 촬영 기록에 속한 사진(대표 사진/방향/개수 표시용).
///
/// 여러 기록을 한 화면에 나열할 때 기록 수만큼 이 provider를 watch하면 N+1
/// 쿼리가 발생하므로, 그 경우 [timelineProvider]처럼 한 번에 조회하는 batched
/// provider를 사용한다.
final recordPhotosProvider = FutureProvider.autoDispose
    .family<List<BodyPhoto>, String>((ref, recordId) async {
      return ref.watch(bodyPhotoRepositoryProvider).listByRecord(recordId);
    });

/// 촬영 기록과 그 기록에 속한 사진을 묶은 값 객체(홈 타임라인 표시용).
class RecordWithPhotos {
  final PhotoRecord record;
  final List<BodyPhoto> photos;

  const RecordWithPhotos({required this.record, required this.photos});

  /// 기록에 담긴 방향을 촬영 순서(정면→좌→우→후→기타)로 정렬해 반환한다.
  List<BodyPhoto> get orderedPhotos {
    final sorted = [...photos];
    sorted.sort(
      (a, b) => a.direction.index.compareTo(b.direction.index),
    );
    return sorted;
  }
}

/// 촬영 기록 목록 + 기록별 사진을 한 번에 조회해 그룹핑한다.
///
/// 기록마다 [recordPhotosProvider]를 개별 watch하면 기록 수만큼 쿼리가
/// 발생(N+1)하므로, 기록 목록 조회 1회 + 사진 전체 조회 1회로 묶어서 처리한다.
final timelineProvider = FutureProvider.autoDispose<List<RecordWithPhotos>>((
  ref,
) async {
  final recordsFuture = ref.watch(photoRecordRepositoryProvider).listAll();
  final photosFuture = ref.watch(bodyPhotoRepositoryProvider).listAll();
  final records = await recordsFuture;
  final photos = await photosFuture;

  final byRecord = <String, List<BodyPhoto>>{};
  for (final photo in photos) {
    byRecord.putIfAbsent(photo.recordId, () => []).add(photo);
  }

  return records
      .map(
        (r) => RecordWithPhotos(
          record: r,
          photos: byRecord[r.id] ?? const [],
        ),
      )
      .toList();
});
