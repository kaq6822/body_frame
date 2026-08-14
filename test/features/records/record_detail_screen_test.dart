import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
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

  const recordId = 'record-1';
  final shotAt = DateTime(2026, 1, 10);

  setUpAll(() {
    // 호스트에서 sqflite를 실행하기 위한 FFI 백엔드 등록.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp(
      'body_frame_records_test_',
    );
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, storage: storage);

    await records.insert(
      PhotoRecord(
        id: recordId,
        shotAt: shotAt,
        memo: '기존 메모',
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );

    final frontPhotoPath = await storage.saveBytes(
      shotAt: shotAt,
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

  Widget buildApp({String routeRecordId = recordId}) {
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
      ],
      child: MaterialApp(home: RecordDetailScreen(recordId: routeRecordId)),
    );
  }

  testWidgets('촬영 기록 상세 화면이 촬영일/사진 그리드/메모를 표시한다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.photo.front.image'))
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.byKey(const ValueKey(RecordDetailScreen.screenId)),
        findsOneWidget,
      );

      // 등록된 방향(정면)은 슬라이더 첫 장으로, 미등록 방향은 요약 칩으로 알린다.
      expect(
        find.byKey(const ValueKey('records.photo.front.image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.photo.leftSide.empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.photo.rightSide.empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.photo.back.empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.photo.etc.empty')),
        findsOneWidget,
      );

      // 사진에는 기본적으로 정렬 격자가 함께 얹힌다.
      expect(
        find.byKey(const ValueKey('records.photo.front.image.grid.overlay')),
        findsOneWidget,
      );
      // 사진이 한 장뿐이면 넘길 곳이 없어 점을 두지 않는다.
      expect(
        find.byKey(const ValueKey('records.photo.slider.dot.0')),
        findsNothing,
      );

      final memoField = tester.widget<TextField>(
        find.byKey(const ValueKey('records.memo.field')),
      );
      expect(memoField.controller?.text, '기존 메모');
    });
  });

  testWidgets('촬영분이 여러 장이면 좌우로 넘겨 보고 점으로 바로 이동한다', (tester) async {
    // 슬라이더는 3:4 프레임이라 기본 테스트 뷰포트(800x600)에서는 화면 밖으로
    // 넘쳐 제스처 지점이 잡히지 않는다. 실기기 비율(1080x2400 @2.75)을 재현한다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      // 정면·좌측면·우측면 3장. 넘기는 순서는 촬영 순서를 따른다.
      for (final direction in [
        BodyDirection.leftSide,
        BodyDirection.rightSide,
      ]) {
        final path = await storage.saveBytes(
          shotAt: shotAt,
          bytes: _onePixelPng,
          fileName: '${direction.key}.png',
        );
        await photos.insert(
          BodyPhoto(
            id: 'photo-${direction.key}',
            recordId: recordId,
            filePath: path,
            direction: direction,
            createdAt: shotAt,
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.photo.slider'))
            .evaluate()
            .isNotEmpty,
      );

      final slider = find.byKey(const ValueKey('records.photo.slider'));
      expect(
        find.byKey(const ValueKey('records.photo.front.image')),
        findsOneWidget,
      );
      expect(find.text('정면'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('records.photo.slider.dot.2')),
        findsOneWidget,
      );

      // 왼쪽으로 밀면 다음 촬영분(좌측면)으로 넘어간다.
      await tester.drag(slider, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('records.photo.leftSide.image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.photo.front.image')),
        findsNothing,
      );
      expect(find.text('2 / 3'), findsOneWidget);

      // 점을 누르면 그 촬영분으로 바로 이동한다.
      await tester.tap(
        find.byKey(const ValueKey('records.photo.slider.dot.0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('records.photo.front.image')),
        findsOneWidget,
      );
      expect(find.text('1 / 3'), findsOneWidget);

      // 3장이 모두 있으므로 미등록으로 남는 방향은 후면·기타뿐이다.
      expect(
        find.byKey(const ValueKey('records.photo.leftSide.empty')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('records.photo.back.empty')),
        findsOneWidget,
      );
    });
  });

  testWidgets('존재하지 않는 기록 id로 진입하면 기록 작업을 노출하지 않는다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp(routeRecordId: 'missing-record'));
      await pumpUntil(
        tester,
        () => find.text('촬영 기록을 불러오지 못했습니다.').evaluate().isNotEmpty,
      );

      expect(find.byKey(const ValueKey('records.memo.field')), findsNothing);
      expect(find.byKey(const ValueKey('records.delete.button')), findsNothing);
      expect(await records.getById(recordId), isNotNull);
    });
  });

  testWidgets('기록 메모를 수정하고 저장하면 리포지토리에 반영된다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.memo.field'))
            .evaluate()
            .isNotEmpty,
      );

      await tester.enterText(
        find.byKey(const ValueKey('records.memo.field')),
        '수정된 메모',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('records.memo.save.button')),
      );
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
