import 'dart:typed_data';
import 'dart:ui';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:body_frame/features/compare/services/compare_export_sink.dart';

/// compare 테스트 전용 인메모리 Fake 모음.
///
/// `ProviderScope(overrides:)`에서 이 Fake들로 교체해 실제 DB/플러그인
/// 채널 없이도 화면을 검증할 수 있다.
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
  Future<List<PhotoRecord>> listAll() async {
    final list = records.values.toList();
    list.sort((a, b) => b.shotAt.compareTo(a.shotAt));
    return list;
  }
}

class FakeBodyPhotoRepository implements BodyPhotoRepository {
  final Map<String, BodyPhoto> photos = {};

  /// recordId -> 촬영일 매핑(listByDirection 정렬 지원용).
  final Map<String, DateTime> recordShotAt;

  FakeBodyPhotoRepository({this.recordShotAt = const {}});

  @override
  Future<void> insert(BodyPhoto photo) async => photos[photo.id] = photo;

  @override
  Future<void> update(BodyPhoto photo) async => photos[photo.id] = photo;

  @override
  Future<void> delete(String id) async => photos.remove(id);

  @override
  Future<BodyPhoto?> getById(String id) async => photos[id];

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async {
    return photos.values.where((p) => p.recordId == recordId).toList();
  }

  @override
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction) async {
    final list = photos.values
        .where((p) => p.direction == direction)
        .toList();
    list.sort((a, b) {
      final left = recordShotAt[a.recordId];
      final right = recordShotAt[b.recordId];
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
    return list;
  }

  @override
  Future<List<BodyPhoto>> listAll() async => photos.values.toList();
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
  Future<void> share(
    Uint8List bytes, {
    required String name,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    if (failShare) throw Exception('share failed');
    sharedNames.add(name);
  }
}
