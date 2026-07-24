import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';

/// 인메모리 [BodyPhotoRepository] Fake. 회원 화면 위젯 테스트에서 실제
/// sqflite/파일 I/O 없이 사진 조회를 대체한다.
class FakeBodyPhotoRepository implements BodyPhotoRepository {
  final List<BodyPhoto> photos = [];

  /// recordId -> memberId 매핑(listByMember/listByMemberDirection 지원용).
  final Map<String, String> recordMemberId;

  FakeBodyPhotoRepository({Map<String, String>? recordMemberId})
      : recordMemberId = recordMemberId ?? {};

  @override
  Future<void> insert(BodyPhoto photo) async => photos.add(photo);

  @override
  Future<void> update(BodyPhoto photo) async {
    final index = photos.indexWhere((p) => p.id == photo.id);
    if (index != -1) photos[index] = photo;
  }

  @override
  Future<void> delete(String id) async {
    photos.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> deleteByRecord(String recordId) async {
    photos.removeWhere((p) => p.recordId == recordId);
  }

  @override
  Future<BodyPhoto?> getById(String id) async {
    for (final photo in photos) {
      if (photo.id == id) return photo;
    }
    return null;
  }

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async =>
      photos.where((p) => p.recordId == recordId).toList();

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async => photos
      .where((p) => recordMemberId[p.recordId] == memberId)
      .toList();

  @override
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async =>
      photos
          .where((p) =>
              p.direction == direction &&
              recordMemberId[p.recordId] == memberId)
          .toList();
}
