import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';

/// 위젯 테스트용 빈 [PhotoRecordRepository]. 회원 관리 흐름 테스트에서는
/// 촬영 기록이 필요 없으므로 항상 빈 목록을 반환한다.
class FakePhotoRecordRepository implements PhotoRecordRepository {
  @override
  Future<List<PhotoRecord>> listByMember(String memberId) async => [];

  @override
  Future<PhotoRecord?> getById(String id) async => null;

  @override
  Future<void> insert(PhotoRecord record) async {}

  @override
  Future<void> update(PhotoRecord record) async {}

  @override
  Future<void> delete(String id) async {}
}
