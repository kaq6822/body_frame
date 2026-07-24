import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/records/photo_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pump_helpers.dart';

/// 1x1 투명 PNG. 위젯 테스트에서 실제 디코딩 가능한 최소 이미지 파일이 필요할 때 사용.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUAAScY42YAAAAASUVORK5CYII=',
);

void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late PhotoStorageService storage;
  late BodyPhotoRepository photos;
  late PhotoRecordRepository records;

  const memberId = 'member-1';
  const recordId = 'record-1';
  const photoId = 'photo-front';
  final shotAt = DateTime(2026, 1, 10);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp('body_frame_photo_view_test_');
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, photos: photos);

    // photo_records.member_id는 members 테이블을 참조하므로 먼저 회원을 등록한다.
    final members = MemberRepositoryImpl(database: db, storage: storage);
    await members.insert(
      Member(
        id: memberId,
        name: '테스트 회원',
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );

    await records.insert(
      PhotoRecord(
        id: recordId,
        memberId: memberId,
        shotAt: shotAt,
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );

    final photoPath = await storage.saveBytes(
      memberId: memberId,
      bytes: _onePixelPng,
      fileName: 'front.png',
    );
    await photos.insert(
      BodyPhoto(
        id: photoId,
        recordId: recordId,
        filePath: photoPath,
        direction: BodyDirection.front,
        memo: '원본 메모',
        createdAt: shotAt,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
      ],
      child: const MaterialApp(
        home: PhotoViewScreen(
          memberId: memberId,
          recordId: recordId,
          photoId: photoId,
        ),
      ),
    );
  }

  testWidgets('원본 사진 보기 화면이 방향/메모를 표시한다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('records.viewer.image')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const ValueKey(PhotoViewScreen.screenId)), findsOneWidget);
      expect(find.byKey(const ValueKey('records.viewer.image')), findsOneWidget);

      final directionField = tester.widget<DropdownButton<BodyDirection>>(
        find.byKey(const ValueKey('records.viewer.direction.field')),
      );
      expect(directionField.value, BodyDirection.front);

      final memoField = tester.widget<TextField>(
        find.byKey(const ValueKey('records.viewer.memo.field')),
      );
      expect(memoField.controller?.text, '원본 메모');
    });
  });

  testWidgets('촬영 방향을 변경하면 리포지토리에 반영된다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('records.viewer.direction.field')).evaluate().isNotEmpty,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('records.viewer.direction.field')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('records.viewer.direction.field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(BodyDirection.leftSide.label).last);
      // 메뉴 닫힘 애니메이션만 정리한다. 방향 저장은 실제 DB 왕복이 필요해
      // pumpAndSettle만으로는 완료를 기다릴 수 없으므로 아래에서 직접 폴링한다.
      await tester.pump();

      BodyPhoto? updated;
      for (var i = 0; i < 40; i++) {
        updated = await photos.getById(photoId);
        if (updated?.direction == BodyDirection.leftSide) break;
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(updated?.direction, BodyDirection.leftSide);
    });
  });

  testWidgets('사진 메모를 수정하고 저장하면 리포지토리에 반영된다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('records.viewer.memo.field')).evaluate().isNotEmpty,
      );

      await tester.enterText(
        find.byKey(const ValueKey('records.viewer.memo.field')),
        '수정된 사진 메모',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('records.viewer.memo.save.button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('records.viewer.memo.save.button')));

      BodyPhoto? updated;
      for (var i = 0; i < 40; i++) {
        updated = await photos.getById(photoId);
        if (updated?.memo == '수정된 사진 메모') break;
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(updated?.memo, '수정된 사진 메모');
    });
  });
}
