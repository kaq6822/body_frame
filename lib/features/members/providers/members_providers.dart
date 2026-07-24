import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/repositories/member_repository.dart';

/// 정렬 옵션 한국어 라벨. MVP.md 3.2.
extension MemberSortLabel on MemberSort {
  String get label {
    switch (this) {
      case MemberSort.recentShot:
        return '최근 촬영순';
      case MemberSort.name:
        return '이름순';
      case MemberSort.registeredAt:
        return '등록일순';
    }
  }
}

/// 회원 목록 검색어. MVP.md 3.2.
final memberSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

/// 회원 목록 정렬 기준. 기본값은 최근 촬영순.
final memberSortProvider =
    StateProvider.autoDispose<MemberSort>((ref) => MemberSort.recentShot);

/// 검색어/정렬을 반영한 회원 목록. 진행(loading)/성공(data)/실패(error)로
/// 귀결된다(ARCHITECTURE.md §7). 등록/수정/삭제 성공 시 이 provider를
/// invalidate하여 목록을 새로고침한다.
final membersListProvider =
    FutureProvider.autoDispose<List<MemberListItem>>((ref) async {
  final repo = ref.watch(memberRepositoryProvider);
  final query = ref.watch(memberSearchQueryProvider);
  final sort = ref.watch(memberSortProvider);
  return repo.list(
    query: query.trim().isEmpty ? null : query.trim(),
    sort: sort,
  );
});

/// 회원 상세 조회.
final memberDetailProvider =
    FutureProvider.autoDispose.family<Member?, String>((ref, memberId) async {
  return ref.watch(memberRepositoryProvider).getById(memberId);
});

/// 회원의 촬영 기록 목록(최신 촬영일 먼저). MVP.md 6.2.
final memberRecordsProvider = FutureProvider.autoDispose
    .family<List<PhotoRecord>, String>((ref, memberId) async {
  return ref.watch(photoRecordRepositoryProvider).listByMember(memberId);
});

/// 촬영 기록에 속한 사진(대표 사진/방향/개수 표시용).
///
/// compare 화면에서도 사용할 예정이므로 이 provider 자체는 유지한다. 회원
/// 상세 화면처럼 여러 기록을 한 화면에 나열할 때는 기록 수만큼 이 provider를
/// watch하면 N+1 쿼리가 발생하므로, 그 경우 [memberRecordsWithPhotosProvider]
/// 처럼 회원 단위로 한 번에 조회하는 batched provider를 사용한다.
final recordPhotosProvider = FutureProvider.autoDispose
    .family<List<BodyPhoto>, String>((ref, recordId) async {
  return ref.watch(bodyPhotoRepositoryProvider).listByRecord(recordId);
});

/// 촬영 기록과 그 기록에 속한 사진을 묶은 값 객체(회원 상세 화면 표시용).
class MemberRecordWithPhotos {
  final PhotoRecord record;
  final List<BodyPhoto> photos;

  const MemberRecordWithPhotos({required this.record, required this.photos});
}

/// 회원의 촬영 기록 목록 + 기록별 사진을 한 번에 조회해 그룹핑한다.
///
/// 기록마다 [recordPhotosProvider]를 개별 watch하면 기록 수만큼 쿼리가
/// 발생(N+1)하므로, 촬영 기록 목록 조회 1회 + 회원 전체 사진 조회 1회로
/// 묶어서 처리한다(BodyPhotoRepository.listByMember).
final memberRecordsWithPhotosProvider = FutureProvider.autoDispose
    .family<List<MemberRecordWithPhotos>, String>((ref, memberId) async {
  final recordsFuture =
      ref.watch(photoRecordRepositoryProvider).listByMember(memberId);
  final photosFuture =
      ref.watch(bodyPhotoRepositoryProvider).listByMember(memberId);
  final records = await recordsFuture;
  final photos = await photosFuture;

  final byRecord = <String, List<BodyPhoto>>{};
  for (final photo in photos) {
    byRecord.putIfAbsent(photo.recordId, () => []).add(photo);
  }

  return records
      .map((r) => MemberRecordWithPhotos(
            record: r,
            photos: byRecord[r.id] ?? const [],
          ))
      .toList();
});
