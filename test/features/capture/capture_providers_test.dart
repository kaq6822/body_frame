import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/capture/providers/capture_providers.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 이전 사진 가이드 provider 테스트.
///
/// 촬영 화면은 앱의 루트라 저장·삭제를 오가는 동안 계속 살아 있다. 구독을
/// 유지한 채로도 기록 변화가 가이드에 반영되는지가 이 테스트의 관심사다.
void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late PhotoStorageService storage;
  late BodyPhotoRepository photos;
  late PhotoRecordRepository records;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp(
      'body_frame_capture_providers_test_',
    );
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, storage: storage);
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// 정면 사진 한 장짜리 기록을 저장하고 원본 경로를 돌려준다.
  Future<String> saveFrontRecord({
    required String id,
    required DateTime shotAt,
  }) async {
    await records.insert(
      PhotoRecord(
        id: id,
        shotAt: shotAt,
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );
    final path = await storage.saveBytes(
      shotAt: shotAt,
      bytes: await _solidPngBytes(4, 3),
      fileName: '$id-front.png',
    );
    await photos.insert(
      BodyPhoto(
        id: '$id-front',
        recordId: id,
        filePath: path,
        direction: BodyDirection.front,
        width: 4,
        height: 3,
        createdAt: shotAt,
      ),
    );
    return path;
  }

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('새 촬영이 저장되면 가이드가 방금 찍은 사진을 가리킨다', () async {
    final older = await saveFrontRecord(id: 'r1', shotAt: DateTime(2026, 1, 10));
    final container = buildContainer();

    // 촬영 화면이 떠 있는 동안을 재현한다. 구독이 살아 있으면 autoDispose가
    // 값을 버리지 않으므로, 무효화 신호가 없으면 옛 경로가 그대로 남는다.
    final guide = previousPhotoGuidePathProvider(BodyDirection.front);
    final sub = container.listen(guide, (_, _) {});
    addTearDown(sub.close);

    expect(await container.read(guide.future), older);

    // 촬영 후 저장(capture_review_screen)이 하는 일과 같다.
    final newer = await saveFrontRecord(id: 'r2', shotAt: DateTime(2026, 2, 10));
    container.invalidate(timelineProvider);

    expect(await container.read(guide.future), newer);
  });

  test('사진이 삭제되면 가이드가 남아 있는 이전 사진으로 물러난다', () async {
    final older = await saveFrontRecord(id: 'r1', shotAt: DateTime(2026, 1, 10));
    final newer = await saveFrontRecord(id: 'r2', shotAt: DateTime(2026, 2, 10));
    final container = buildContainer();

    final guide = previousPhotoGuidePathProvider(BodyDirection.front);
    final sub = container.listen(guide, (_, _) {});
    addTearDown(sub.close);

    expect(await container.read(guide.future), newer);

    await photos.delete('r2-front');
    container.invalidate(timelineProvider);

    expect(await container.read(guide.future), older);
  });
}

/// 실제로 열리는 최소 PNG. 가이드 provider가 파일 존재와 크기를 확인한다.
Future<Uint8List> _solidPngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
