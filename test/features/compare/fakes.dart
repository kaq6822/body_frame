import 'dart:typed_data';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:body_frame/features/compare/services/compare_export_sink.dart';

/// compare 워커 테스트 전용 인메모리 Fake 모음.
///
/// ARCHITECTURE.md §8: 리포지토리/서비스는 추상 인터페이스이므로
/// `ProviderScope(overrides:)`에서 이 Fake들로 교체해 실제 DB/플러그인
/// 채널 없이도 화면을 검증할 수 있다.
class FakeMemberRepository implements MemberRepository {
  final Map<String, Member> members = {};

  @override
  Future<void> insert(Member member) async => members[member.id] = member;

  @override
  Future<void> update(Member member) async => members[member.id] = member;

  @override
  Future<void> delete(String id) async => members.remove(id);

  @override
  Future<Member?> getById(String id) async => members[id];

  @override
  Future<List<MemberListItem>> list({
    String? query,
    MemberSort sort = MemberSort.recentShot,
  }) async {
    return members.values
        .map((m) => MemberListItem(member: m, recordCount: 0, lastShotAt: null))
        .toList();
  }
}

class FakePhotoRecordRepository implements PhotoRecordRepository {
  final Map<String, PhotoRecord> records = {};

  @override
  Future<void> insert(PhotoRecord record) async => records[record.id] = record;

  @override
  Future<void> update(PhotoRecord record) async => records[record.id] = record;

  @override
  Future<void> delete(String id) async => records.remove(id);

  @override
  Future<PhotoRecord?> getById(String id) async => records[id];

  @override
  Future<List<PhotoRecord>> listByMember(String memberId) async {
    final list = records.values.where((r) => r.memberId == memberId).toList();
    list.sort((a, b) => b.shotAt.compareTo(a.shotAt));
    return list;
  }
}

class FakeBodyPhotoRepository implements BodyPhotoRepository {
  final Map<String, BodyPhoto> photos = {};

  /// recordId -> memberId 매핑(listByMemberDirection 지원용).
  final Map<String, String> recordMemberId;

  FakeBodyPhotoRepository({this.recordMemberId = const {}});

  @override
  Future<void> insert(BodyPhoto photo) async => photos[photo.id] = photo;

  @override
  Future<void> update(BodyPhoto photo) async => photos[photo.id] = photo;

  @override
  Future<void> delete(String id) async => photos.remove(id);

  @override
  Future<void> deleteByRecord(String recordId) async {
    photos.removeWhere((_, p) => p.recordId == recordId);
  }

  @override
  Future<BodyPhoto?> getById(String id) async => photos[id];

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async {
    return photos.values.where((p) => p.recordId == recordId).toList();
  }

  @override
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async {
    return photos.values.where((p) {
      return p.direction == direction &&
          recordMemberId[p.recordId] == memberId;
    }).toList();
  }

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async {
    return photos.values
        .where((p) => recordMemberId[p.recordId] == memberId)
        .toList();
  }
}

class FakeGridSettingsService implements GridSettingsService {
  GridSettings current;

  FakeGridSettingsService([this.current = GridSettings.defaults]);

  @override
  Future<GridSettings> load() async => current;

  @override
  Future<void> save(GridSettings settings) async => current = settings;

  @override
  Future<void> reset() async => current = GridSettings.defaults;
}

class FakeCompareExportSink implements CompareExportSink {
  final List<String> savedNames = [];
  final List<String> sharedNames = [];
  bool failSave = false;
  bool failShare = false;

  @override
  Future<void> saveToGallery(Uint8List bytes, {required String name}) async {
    if (failSave) throw Exception('save failed');
    savedNames.add(name);
  }

  @override
  Future<void> share(Uint8List bytes, {required String name, String? text}) async {
    if (failShare) throw Exception('share failed');
    sharedNames.add(name);
  }
}
