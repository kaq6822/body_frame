import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/records/photo_view_screen.dart';
import 'package:body_frame/features/records/services/grid_photo_composer.dart';
import 'package:body_frame/features/records/services/photo_export_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pump_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late PhotoStorageService storage;
  late BodyPhotoRepository photos;
  late PhotoRecordRepository records;
  late FakePhotoExportSink exportSink;
  late FakeGridPhotoComposer gridComposer;

  const recordId = 'record-1';
  const photoId = 'photo-front';
  final shotAt = DateTime(2026, 1, 10);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp(
      'body_frame_photo_view_test_',
    );
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, storage: storage);
    exportSink = FakePhotoExportSink();
    gridComposer = FakeGridPhotoComposer(
      await _solidPngBytes(4, 3, color: const ui.Color(0xFFCC3300)),
    );

    await records.insert(
      PhotoRecord(
        id: recordId,
        shotAt: shotAt,
        createdAt: shotAt,
        updatedAt: shotAt,
      ),
    );

    final photoPath = await storage.saveBytes(
      shotAt: shotAt,
      bytes: await _solidPngBytes(4, 3),
      fileName: 'front.png',
    );
    await photos.insert(
      BodyPhoto(
        id: photoId,
        recordId: recordId,
        filePath: photoPath,
        direction: BodyDirection.front,
        width: 4,
        height: 3,
        gridSettings: const GridSettings(
          visible: false,
          opacity: 1,
          lineWidth: 2,
          spacing: 40,
        ),
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

  Widget buildApp({
    String routeRecordId = recordId,
    String routePhotoId = photoId,
    AppImagePickerCoordinator? pickerCoordinator,
  }) {
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        photoStorageServiceProvider.overrideWithValue(storage),
        photoExportSinkProvider.overrideWithValue(exportSink),
        gridPhotoComposerProvider.overrideWithValue(gridComposer),
        if (pickerCoordinator != null)
          appImagePickerCoordinatorProvider.overrideWith(
            (ref) => pickerCoordinator,
          ),
      ],
      child: MaterialApp(
        home: PhotoViewScreen(
          recordId: routeRecordId,
          photoId: routePhotoId,
        ),
      ),
    );
  }

  testWidgets('원본 사진 보기 화면이 방향/메모를 표시한다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.viewer.image'))
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.byKey(const ValueKey(PhotoViewScreen.screenId)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('records.viewer.image')),
        findsOneWidget,
      );

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

  testWidgets('URL의 기록과 사진 소유관계가 다르면 사진 작업을 노출하지 않는다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp(routeRecordId: 'other-record'));
      await pumpUntil(
        tester,
        () => find.text('사진 정보를 불러오지 못했습니다.').evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('records.viewer.replace.button')),
        findsNothing,
      );
      expect((await photos.getById(photoId))?.recordId, recordId);
    });
  });

  testWidgets('촬영 방향을 변경하면 리포지토리에 반영된다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.viewer.direction.field'))
            .evaluate()
            .isNotEmpty,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('records.viewer.direction.field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('records.viewer.direction.field')),
      );
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
        () => find
            .byKey(const ValueKey('records.viewer.memo.field'))
            .evaluate()
            .isNotEmpty,
      );

      await tester.enterText(
        find.byKey(const ValueKey('records.viewer.memo.field')),
        '수정된 사진 메모',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('records.viewer.memo.save.button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('records.viewer.memo.save.button')),
      );

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

  testWidgets('유실된 교체 사진은 명시적으로 적용하기 전까지 기존 원본을 유지한다', (tester) async {
    await tester.runAsync(() async {
      final replacementBytes = await _solidPngBytes(
        7,
        5,
        color: const ui.Color(0xFF33AA44),
      );
      final replacementFile = await File(
        '${tempRoot.path}/replacement.png',
      ).writeAsBytes(replacementBytes);
      final original = (await photos.getById(photoId))!;
      final originalBytes = await File(original.filePath).readAsBytes();

      final request = ImagePickerRequestContext.photoReplacement(
        recordId: recordId,
        photoId: photoId,
      );
      final pickerCoordinator = AppImagePickerCoordinator(
        picker: _LostReplacementPicker(replacementFile),
        requestStore: _MemoryRequestStore(request),
      );
      await pickerCoordinator.initialize();

      await tester.pumpWidget(buildApp(pickerCoordinator: pickerCoordinator));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.viewer.replace.pending.card'))
            .evaluate()
            .isNotEmpty,
      );

      final beforeConfirmation = (await photos.getById(photoId))!;
      expect(beforeConfirmation.filePath, original.filePath);
      expect(
        await File(beforeConfirmation.filePath).readAsBytes(),
        orderedEquals(originalBytes),
      );

      final confirm = find.byKey(
        const ValueKey('records.viewer.replace.confirm.button'),
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();

      BodyPhoto? replaced;
      for (var i = 0; i < 60; i++) {
        replaced = await photos.getById(photoId);
        if (replaced?.filePath != original.filePath) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(replaced?.recordId, recordId);
      expect(replaced?.filePath, isNot(original.filePath));
      expect(
        await File(replaced!.filePath).readAsBytes(),
        orderedEquals(replacementBytes),
      );
    });
  });

  testWidgets('격자 옵션을 끄면 원본 파일 경로를 그대로 내보낸다', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.viewer.export.button'))
            .evaluate()
            .isNotEmpty,
      );

      final exportButton = find.byKey(
        const ValueKey('records.viewer.export.button'),
      );
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      for (var i = 0; i < 40 && exportSink.originalPaths.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(exportSink.originalPaths, hasLength(1));
      expect(exportSink.pngBytes, isEmpty);
      expect(
        exportSink.originalPaths.single,
        (await photos.getById(photoId))!.filePath,
      );
    });
  });

  testWidgets('격자 옵션은 원본을 유지하고 격자가 합성된 별도 PNG를 내보낸다', (tester) async {
    await tester.runAsync(() async {
      final photo = (await photos.getById(photoId))!;
      final originalFile = File(photo.filePath);
      final originalBytes = await originalFile.readAsBytes();

      await tester.pumpWidget(buildApp());
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('records.viewer.export.grid.toggle'))
            .evaluate()
            .isNotEmpty,
      );

      final gridToggle = find.byKey(
        const ValueKey('records.viewer.export.grid.toggle'),
      );
      await tester.ensureVisible(gridToggle);
      await tester.tap(gridToggle);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('records.viewer.export.grid.preview')),
        findsOneWidget,
      );

      final exportButton = find.byKey(
        const ValueKey('records.viewer.export.button'),
      );
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      for (var i = 0; i < 60 && exportSink.pngBytes.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump(const Duration(milliseconds: 25));
      }

      expect(exportSink.originalPaths, isEmpty);
      expect(exportSink.pngBytes, hasLength(1));
      expect(exportSink.pngNames.single, contains('_grid'));
      expect(gridComposer.sourceBytes, hasLength(1));
      expect(gridComposer.settings.single.visible, isFalse);
      expect(exportSink.pngBytes.single, isNot(orderedEquals(originalBytes)));
      expect(await originalFile.readAsBytes(), orderedEquals(originalBytes));
    });
  });
}

Future<Uint8List> _solidPngBytes(
  int width,
  int height, {
  ui.Color color = const ui.Color(0xFF336699),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class FakeGridPhotoComposer implements GridPhotoComposer {
  final Uint8List result;
  final List<Uint8List> sourceBytes = [];
  final List<GridSettings> settings = [];

  FakeGridPhotoComposer(this.result);

  @override
  Future<Uint8List> compose(
    Uint8List sourceBytes,
    GridSettings settings,
  ) async {
    this.sourceBytes.add(Uint8List.fromList(sourceBytes));
    this.settings.add(settings);
    return Uint8List.fromList(result);
  }
}

class FakePhotoExportSink implements PhotoExportSink {
  final List<String> originalPaths = [];
  final List<Uint8List> pngBytes = [];
  final List<String> pngNames = [];

  @override
  Future<void> saveOriginalFile(
    String sourcePath, {
    required String name,
  }) async {
    originalPaths.add(sourcePath);
  }

  @override
  Future<void> savePng(Uint8List bytes, {required String name}) async {
    pngBytes.add(Uint8List.fromList(bytes));
    pngNames.add(name);
  }
}

class _LostReplacementPicker implements AppImagePicker {
  final File file;

  _LostReplacementPicker(this.file);

  @override
  bool get supportsLostDataRecovery => true;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;

  @override
  Future<List<XFile>> pickMultiImage() async => const [];

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return LostDataResponse(file: XFile(file.path));
  }
}

class _MemoryRequestStore implements ImagePickerRequestStore {
  ImagePickerRequestContext? current;

  _MemoryRequestStore(this.current);

  @override
  Future<void> clear() async => current = null;

  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {
    if (current == context) current = null;
  }

  @override
  Future<ImagePickerRequestContext?> load() async => current;

  @override
  Future<void> save(ImagePickerRequestContext context) async {
    current = context;
  }
}
