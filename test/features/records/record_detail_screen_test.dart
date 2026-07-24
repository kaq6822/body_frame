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
import 'package:body_frame/features/records/record_detail_screen.dart';
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
  final shotAt = DateTime(2026, 1, 10);

  setUpAll(() {
    // 호스트에서 sqflite를 실행하기 위한 FFI 백엔드 등록.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp('body_frame_records_test_');
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
        memo: '기존 메모',
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );

    final frontPhotoPath = await storage.saveBytes(
      memberId: memberId,
      bytes: _onePixelPng,
      fileName: 'front.png',
    );
    await photos.insert(
      BodyPhoto(
        id: 'photo-front',
        recordId: recordId,
        filePath: frontPhotoPath,
        direction: BodyDirection.front,
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
        home: RecordDetailScreen(memberId: memberId, recordId: recordId),
      ),
    );
  }

  testWidgets('촬영 기록 상세 화면이 촬영일/사진 그리드/메모를 표시한다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('records.photo.front.image')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const ValueKey(RecordDetailScreen.screenId)), findsOneWidget);

      // 등록된 방향(정면)은 사진 타일로, 미등록 방향은 빈 타일로 표시된다.
      expect(find.byKey(const ValueKey('records.photo.front.image')), findsOneWidget);
      expect(find.byKey(const ValueKey('records.photo.leftSide.empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('records.photo.rightSide.empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('records.photo.back.empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('records.photo.etc.empty')), findsOneWidget);

      final memoField =
          tester.widget<TextField>(find.byKey(const ValueKey('records.memo.field')));
      expect(memoField.controller?.text, '기존 메모');
    });
  });

  testWidgets('기록 메모를 수정하고 저장하면 리포지토리에 반영된다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('records.memo.field')).evaluate().isNotEmpty,
      );

      await tester.enterText(
        find.byKey(const ValueKey('records.memo.field')),
        '수정된 메모',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('records.memo.save.button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('records.memo.save.button')));

      // 저장 처리가 실제 DB에 반영될 때까지 리포지토리 값을 직접 폴링한다.
      PhotoRecord? updated;
      for (var i = 0; i < 40; i++) {
        updated = await records.getById(recordId);
        if (updated?.memo == '수정된 메모') break;
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(updated?.memo, '수정된 메모');
    });
  });
}
