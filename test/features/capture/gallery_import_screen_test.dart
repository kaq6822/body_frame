import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/photo_ingest_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/capture/gallery_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File recoveredImage;
  late File secondImage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'body_frame_picker_recovery_',
    );
    recoveredImage = File('${tempDir.path}/recovered.png');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    await recoveredImage.writeAsBytes(byteData!.buffer.asUint8List());
    secondImage = await recoveredImage.copy('${tempDir.path}/second.png');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxTries = 40,
  }) async {
    for (var i = 0; i < maxTries && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  /// 사진 목록을 고르고 저장 버튼을 누를 수 있게 준비한다.
  ///
  /// [saveGate]를 주면 저장이 그 지점에서 멈춰 "저장 중" 구간을 만든다.
  Future<
    ({
      ProviderContainer container,
      _FakePhotoRecordRepository records,
      _FakePhotoIngestRepository ingest,
      _FakePhotoStorageService storage,
      _FakeAppImagePicker picker,
      _TestImagePickerCoordinator coordinator,
    })
  >
  prepareImport(
    WidgetTester tester, {
    required List<File> files,
    _FakePhotoIngestRepository? ingest,
    _FakePhotoStorageService? storage,
    Completer<void>? saveGate,
    bool withNavigation = false,
  }) async {
    final picker = _FakeAppImagePicker(
      LostDataResponse.empty(),
      supportsLostDataRecovery: false,
      pickedFiles: [for (final file in files) XFile(file.path)],
    );
    final coordinator = _TestImagePickerCoordinator(
      picker: picker,
      requestStore: _MemoryImagePickerRequestStore(null),
    );
    await coordinator.initialize();
    final records = _FakePhotoRecordRepository();
    final ingestRepo = ingest ?? _FakePhotoIngestRepository(records);
    final storageService = storage ?? _FakePhotoStorageService(tempDir);
    storageService.saveGate = saveGate;
    final container = ProviderContainer(
      overrides: [
        appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingestRepo),
        photoStorageServiceProvider.overrideWithValue(storageService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withNavigation
            ? MaterialApp(
                initialRoute: '/import',
                routes: {
                  '/': (_) => const Scaffold(body: Text('home')),
                  '/import': (_) => const GalleryImportScreen(),
                },
              )
            : const MaterialApp(home: GalleryImportScreen()),
      ),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.pick.button'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('capture.import.pick.button')));
    await pumpUntil(
      tester,
      () => find
          .byKey(ValueKey('capture.import.item.${files.length - 1}.card'))
          .evaluate()
          .isNotEmpty,
    );
    return (
      container: container,
      records: records,
      ingest: ingestRepo,
      storage: storageService,
      picker: picker,
      coordinator: coordinator,
    );
  }

  testWidgets('Android Activity 종료로 유실된 사진 선택 결과를 화면 재생성 시 복구한다', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
      'ASsJTYQAAAAASUVORK5CYII=',
    );
    final picker = _FakeAppImagePicker(
      LostDataResponse(
        files: [XFile.fromData(bytes, path: recoveredImage.path)],
      ),
    );
    final store = _MemoryImagePickerRequestStore(
      ImagePickerRequestContext.galleryImport(),
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    await coordinator.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: const MaterialApp(home: GalleryImportScreen()),
      ),
    );
    for (
      var i = 0;
      i < 10 &&
          find
              .byKey(const ValueKey('capture.import.item.0.card'))
              .evaluate()
              .isEmpty;
      i += 1
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(picker.retrieveLostDataCalls, 1);
    expect(find.byKey(const ValueKey('capture.import.list')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('capture.import.item.0.card')),
      findsOneWidget,
    );
  });

  testWidgets('모든 파일과 메타를 준비한 뒤 사진 두 장을 한 번의 ingest로 등록한다', (tester) async {
    final picker = _FakeAppImagePicker(
      LostDataResponse.empty(),
      supportsLostDataRecovery: false,
      pickedFiles: [XFile(recoveredImage.path), XFile(secondImage.path)],
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: _MemoryImagePickerRequestStore(null),
    );
    await coordinator.initialize();
    final records = _FakePhotoRecordRepository();
    final ingest = _FakePhotoIngestRepository(records);
    final storage = _FakePhotoStorageService(tempDir);
    final container = ProviderContainer(
      overrides: [
        appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingest),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GalleryImportScreen()),
      ),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.pick.button'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('capture.import.pick.button')));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.item.1.card'))
          .evaluate()
          .isNotEmpty,
    );
    for (var index = 0; index < 2; index += 1) {
      final direction = find.byKey(
        ValueKey('capture.import.item.$index.direction.front.button'),
      );
      await tester.ensureVisible(direction);
      await tester.tap(direction);
      await tester.pump();
    }
    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(tester, () => ingest.calls == 1);

    expect(ingest.calls, 1);
    expect(ingest.lastNewRecords, hasLength(1));
    expect(ingest.photos, hasLength(2));
    expect(ingest.allFilesExistedAtCall, isTrue);
    expect(ingest.photos.map((photo) => photo.recordId).toSet(), hasLength(1));
    expect(recoveredImage.existsSync(), isTrue);
    expect(secondImage.existsSync(), isTrue);
  });

  testWidgets('촬영일이 같은 기존 기록이 있어도 이 등록 건은 새 기록으로 만든다', (tester) async {
    final picker = _FakeAppImagePicker(
      LostDataResponse.empty(),
      supportsLostDataRecovery: false,
      pickedFiles: [XFile(recoveredImage.path)],
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: _MemoryImagePickerRequestStore(null),
    );
    await coordinator.initialize();
    final records = _FakePhotoRecordRepository();
    final ingest = _FakePhotoIngestRepository(records);
    final storage = _FakePhotoStorageService(tempDir);
    // 화면이 제안하는 촬영일은 EXIF가 없으면 오늘이다. 같은 날 기존 기록을 둔다.
    final today = DateTime.now();
    records.records.add(
      PhotoRecord(
        id: 'r-existing',
        shotAt: DateTime(today.year, today.month, today.day),
        createdAt: today,
        updatedAt: today,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingest),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GalleryImportScreen()),
      ),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.pick.button'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('capture.import.pick.button')));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.item.0.card'))
          .evaluate()
          .isNotEmpty,
    );
    final direction = find.byKey(
      const ValueKey('capture.import.item.0.direction.front.button'),
    );
    await tester.ensureVisible(direction);
    await tester.tap(direction);
    await tester.pump();
    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(tester, () => ingest.calls == 1);

    expect(ingest.lastNewRecords, hasLength(1));
    expect(ingest.lastNewRecords.single.id, isNot('r-existing'));
    expect(ingest.photos.single.recordId, ingest.lastNewRecords.single.id);
  });

  testWidgets('저장 중에는 항목 제거·방향·날짜·메모 변경과 재저장이 모두 막힌다', (tester) async {
    final gate = Completer<void>();
    final context = await prepareImport(
      tester,
      files: [recoveredImage, secondImage],
      saveGate: gate,
    );

    for (var index = 0; index < 2; index += 1) {
      final direction = find.byKey(
        ValueKey('capture.import.item.$index.direction.front.button'),
      );
      await tester.ensureVisible(direction);
      await tester.tap(direction);
      await tester.pump();
    }

    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(tester, () => context.storage.savedFrom.isNotEmpty);
    await tester.pump();

    // 저장이 시작되며 모든 조작이 막힌다.
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('capture.import.item.0.remove.button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('capture.import.item.0.date.field')),
          )
          .onPressed,
      isNull,
    );
    // TextFormField는 readOnly를 필드로 노출하지 않는다. 그 안의 TextField를 본다.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(
                const ValueKey('capture.import.item.0.memo.field'),
              ),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('capture.import.save.button')),
          )
          .onPressed,
      isNull,
    );

    // 비활성 컨트롤을 강제로 눌러도 목록과 저장은 바뀌지 않는다.
    await tester.tap(
      find.byKey(const ValueKey('capture.import.item.0.remove.button')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('capture.import.item.0.direction.back.button')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('capture.import.save.button')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('capture.import.item.1.card')),
      findsOneWidget,
    );

    gate.complete();
    await pumpUntil(tester, () => context.ingest.calls == 1);

    // 중복 저장은 없고, 저장된 두 장의 방향은 저장 시작 시점 값이다.
    expect(context.ingest.calls, 1);
    expect(context.ingest.photos, hasLength(2));
    expect(
      context.ingest.photos.map((photo) => photo.direction),
      everyElement(BodyDirection.front),
    );
    // 성공하면 저장한 항목만 목록에서 빠지고 빈 안내가 남는다.
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('capture.import.item.0.card')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('capture.import.empty')), findsOneWidget);
  });

  testWidgets('저장 중 사진 선택 버튼이 비활성화된다', (tester) async {
    final gate = Completer<void>();
    final context = await prepareImport(
      tester,
      files: [recoveredImage, secondImage],
      saveGate: gate,
    );
    for (var index = 0; index < 2; index += 1) {
      final direction = find.byKey(
        ValueKey('capture.import.item.$index.direction.front.button'),
      );
      await tester.ensureVisible(direction);
      await tester.tap(direction);
      await tester.pump();
    }
    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(tester, () => context.storage.savedFrom.isNotEmpty);
    await tester.pump();

    // 저장이 진행 중이라 사진 선택 버튼도 막힌다.
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('capture.import.pick.button')),
          )
          .onPressed,
      isNull,
    );

    gate.complete();
    await pumpUntil(tester, () => context.ingest.calls == 1);
    await tester.pumpAndSettle();

    // 저장 대상은 시작 시점 목록 그대로 두 장이다.
    expect(context.ingest.photos, hasLength(2));
    expect(context.storage.savedFrom, [recoveredImage.path, secondImage.path]);
    // 성공한 뒤 목록이 비워진다.
    expect(find.byKey(const ValueKey('capture.import.empty')), findsOneWidget);
  });

  testWidgets('저장 중 방향을 바꾸어도 저장 시작 시점의 값이 기록된다', (tester) async {
    final gate = Completer<void>();
    final context = await prepareImport(
      tester,
      files: [recoveredImage],
      saveGate: gate,
    );
    final direction = find.byKey(
      const ValueKey('capture.import.item.0.direction.front.button'),
    );
    await tester.ensureVisible(direction);
    await tester.tap(direction);
    await tester.pump();
    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(tester, () => context.storage.savedFrom.isNotEmpty);
    await tester.pump();

    // 저장이 끝난 뒤 방향을 바꾸도 이미 진행 중인 저장은 바뀌지 않는다.
    await tester.tap(
      find.byKey(const ValueKey('capture.import.item.0.direction.back.button')),
      warnIfMissed: false,
    );
    gate.complete();
    await pumpUntil(tester, () => context.ingest.calls == 1);

    expect(context.ingest.photos.single.direction, BodyDirection.front);
  });

  testWidgets('ingest 실패 시 준비한 모든 관리 파일을 정리하고 DB fake를 변경하지 않는다', (
    tester,
  ) async {
    final picker = _FakeAppImagePicker(
      LostDataResponse.empty(),
      supportsLostDataRecovery: false,
      pickedFiles: [XFile(recoveredImage.path), XFile(secondImage.path)],
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: _MemoryImagePickerRequestStore(null),
    );
    await coordinator.initialize();
    final records = _FakePhotoRecordRepository();
    final ingest = _FakePhotoIngestRepository(records, fail: true);
    final storage = _FakePhotoStorageService(tempDir);
    final container = ProviderContainer(
      overrides: [
        appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingest),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GalleryImportScreen()),
      ),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.pick.button'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('capture.import.pick.button')));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('capture.import.item.1.card'))
          .evaluate()
          .isNotEmpty,
    );
    for (var index = 0; index < 2; index += 1) {
      final direction = find.byKey(
        ValueKey('capture.import.item.$index.direction.front.button'),
      );
      await tester.ensureVisible(direction);
      await tester.tap(direction);
      await tester.pump();
    }
    final save = find.byKey(const ValueKey('capture.import.save.button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('screen.capture.import.status.retry.button'))
          .evaluate()
          .isNotEmpty,
    );

    expect(ingest.calls, 1);
    expect(ingest.allFilesExistedAtCall, isTrue);
    expect(records.records, isEmpty);
    expect(ingest.photos, isEmpty);
    final managed = Directory(p.join(tempDir.path, 'photos'));
    expect(
      managed.existsSync()
          ? managed
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
          : const <File>[],
      isEmpty,
    );
    expect(recoveredImage.existsSync(), isTrue);
    expect(secondImage.existsSync(), isTrue);
  });
  testWidgets('사진 선택 중에는 저장 버튼과 이전 저장 콜백이 모두 차단된다', (tester) async {
    final saveGate = Completer<void>();
    final pickGate = Completer<List<XFile>>();
    final ctx = await prepareImport(
      tester,
      files: [recoveredImage],
      saveGate: saveGate,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('capture.import.item.0.direction.front.button'),
      ),
    );
    await tester.pump();
    final saveFinder = find.byKey(const ValueKey('capture.import.save.button'));
    final previousSave = tester.widget<FilledButton>(saveFinder).onPressed!;
    ctx.picker.pickGate = pickGate;
    await tester.tap(find.byKey(const ValueKey('capture.import.pick.button')));
    await tester.pump();
    final saveDisabled =
        tester.widget<FilledButton>(saveFinder).onPressed == null;
    previousSave();
    await tester.pump();
    final saveStarted = ctx.storage.savedFrom.isNotEmpty;
    pickGate.complete([XFile(secondImage.path)]);
    saveGate.complete();
    await pumpUntil(
      tester,
      () =>
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('capture.import.pick.button')),
              )
              .onPressed !=
          null,
    );
    expect(saveDisabled, isTrue);
    expect(saveStarted, isFalse);
    expect(ctx.ingest.calls, 0);
    final preview = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('capture.import.item.0.card')),
        matching: find.byType(Image),
      ),
    );
    expect((preview.image as FileImage).file.path, secondImage.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('갤러리 저장 중 시스템·앱바 뒤로가기를 막고 완료 후 다시 허용한다', (tester) async {
    final gate = Completer<void>();
    final ctx = await prepareImport(
      tester,
      files: [recoveredImage],
      saveGate: gate,
      withNavigation: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('capture.import.item.0.direction.front.button'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.import.save.button')));
    await pumpUntil(tester, () => ctx.storage.savedFrom.isNotEmpty);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    final stayedAfterSystemBack = find
        .byType(GalleryImportScreen)
        .evaluate()
        .isNotEmpty;
    if (stayedAfterSystemBack) {
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 300));
    }
    final stayedAfterAppBarBack = find
        .byType(GalleryImportScreen)
        .evaluate()
        .isNotEmpty;
    gate.complete();
    await pumpUntil(tester, () => ctx.ingest.calls == 1);
    await tester.pumpAndSettle();
    expect(stayedAfterSystemBack, isTrue);
    expect(stayedAfterAppBarBack, isTrue);
    expect(ctx.ingest.calls, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryImportScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('저장 중 도착한 복구 결과는 저장 완료 후 목록에 반영한다', (tester) async {
    final gate = Completer<void>();
    final ctx = await prepareImport(
      tester,
      files: [recoveredImage],
      saveGate: gate,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('capture.import.item.0.direction.front.button'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.import.save.button')));
    await pumpUntil(tester, () => ctx.storage.savedFrom.isNotEmpty);
    await tester.pump();
    ctx.coordinator.deliverRecovered([XFile(secondImage.path)]);
    await tester.pump();
    await tester.pump();
    final requestContext = ImagePickerRequestContext.galleryImport();
    expect(ctx.coordinator.recoveredFor(requestContext), isNotNull);
    gate.complete();
    await pumpUntil(
      tester,
      () =>
          ctx.ingest.calls == 1 &&
          ctx.coordinator.recoveredFor(requestContext) == null,
    );
    final card = find.byKey(const ValueKey('capture.import.item.0.card'));
    expect(card, findsOneWidget);
    final preview = tester.widget<Image>(
      find.descendant(of: card, matching: find.byType(Image)),
    );
    expect((preview.image as FileImage).file.path, secondImage.path);
    expect(ctx.ingest.photos, hasLength(1));
    expect(ctx.storage.savedFrom, [recoveredImage.path]);
    expect(ctx.coordinator.recoveredFor(requestContext), isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('capture.import.pick.button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('저장 실패 시 대기 중 복구 결과가 재시도 목록을 덮어쓰지 않는다', (tester) async {
    final gate = Completer<void>();
    final ctx = await prepareImport(
      tester,
      files: [recoveredImage],
      saveGate: gate,
      ingest: _FakePhotoIngestRepository(
        _FakePhotoRecordRepository(),
        fail: true,
      ),
      withNavigation: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('capture.import.item.0.direction.front.button'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.import.save.button')));
    await pumpUntil(tester, () => ctx.storage.savedFrom.isNotEmpty);
    ctx.coordinator.deliverRecovered([XFile(secondImage.path)]);
    await tester.pump();
    gate.complete();
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('screen.capture.import.status.retry.button'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('capture.import.item.0.card')),
        matching: find.byType(Image),
      ),
    );
    expect((preview.image as FileImage).file.path, recoveredImage.path);
    expect(recoveredImage.existsSync(), isTrue);
    expect(
      ctx.coordinator.recoveredFor(ImagePickerRequestContext.galleryImport()),
      isNotNull,
    );
    expect(ctx.ingest.photos, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryImportScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAppImagePicker implements AppImagePicker {
  final LostDataResponse response;
  final List<XFile> pickedFiles;
  @override
  final bool supportsLostDataRecovery;
  int retrieveLostDataCalls = 0;
  Completer<List<XFile>>? pickGate;

  _FakeAppImagePicker(
    this.response, {
    this.pickedFiles = const [],
    this.supportsLostDataRecovery = true,
  });

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;

  @override
  Future<List<XFile>> pickMultiImage() async =>
      pickGate == null ? pickedFiles : await pickGate!.future;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCalls += 1;
    return response;
  }
}

class _FakePhotoRecordRepository implements PhotoRecordRepository {
  final List<PhotoRecord> records = [];

  @override
  Future<void> delete(String id) async {
    records.removeWhere((record) => record.id == id);
  }

  @override
  Future<PhotoRecord?> getById(String id) async =>
      records.where((record) => record.id == id).firstOrNull;

  @override
  Future<void> insert(PhotoRecord record) async {
    records.add(record);
  }

  @override
  Future<List<PhotoRecord>> listAll() async => List.of(records);

  @override
  Future<void> update(PhotoRecord record) async {
    final index = records.indexWhere((candidate) => candidate.id == record.id);
    if (index >= 0) records[index] = record;
  }
}

class _FakePhotoIngestRepository implements PhotoIngestRepository {
  final _FakePhotoRecordRepository records;
  final bool fail;
  final List<BodyPhoto> photos = [];
  int calls = 0;
  bool allFilesExistedAtCall = false;
  List<PhotoRecord> lastNewRecords = const [];

  _FakePhotoIngestRepository(this.records, {this.fail = false});

  @override
  Future<void> insertPrepared({
    required List<PhotoRecord> newRecords,
    required List<BodyPhoto> photos,
  }) async {
    calls += 1;
    allFilesExistedAtCall = photos.every(
      (photo) => File(photo.filePath).existsSync(),
    );
    lastNewRecords = List.unmodifiable(newRecords);
    if (fail) throw StateError('transaction 실패(테스트)');
    records.records.addAll(newRecords);
    this.photos.addAll(photos);
  }
}

class _FakePhotoStorageService implements PhotoStorageService {
  /// 실제 staging 디렉터리를 두지 않는 fake다. 정리할 것이 없다.
  @override
  Future<int> cleanupStagingLeftovers() async => 0;

  final Directory root;

  /// 저장 요청이 들어온 원본 경로.
  final List<String> savedFrom = [];

  /// 저장을 이 지연까지 멈춰 세운다. 저장 중 목록 조작을 검증할 때 쓴다.
  /// 실제 시간 지연이 아니라 명시적으로 완료시켜 결정론적으로 만든다.
  Completer<void>? saveGate;

  _FakePhotoStorageService(this.root);

  @override
  Future<Directory> bucketDir(DateTime shotAt) async {
    final directory = Directory(
      p.join(root.path, 'photos', PhotoStorageServiceImpl.bucketName(shotAt)),
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String> saveOriginal({
    required DateTime shotAt,
    required String sourcePath,
    String? fileName,
  }) async {
    savedFrom.add(sourcePath);
    final directory = await bucketDir(shotAt);
    final copied = await File(
      sourcePath,
    ).copy(p.join(directory.path, fileName ?? p.basename(sourcePath)));
    final gate = saveGate;
    if (gate != null) {
      // 복사는 이미 끝난 뒤 멈춘다. 저장이 "진행 중"인 구간을 만든다.
      await gate.future;
    }
    return copied.path;
  }

  @override
  Future<String> saveBytes({
    required DateTime shotAt,
    required List<int> bytes,
    required String fileName,
  }) async {
    final directory = await bucketDir(shotAt);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<String> resolvePath(String storedPath) async {
    if (p.isAbsolute(storedPath)) return storedPath;
    return p.joinAll([root.path, ...p.posix.split(storedPath)]);
  }

  @override
  Future<String> toStoredPath(String filePath) async {
    final photosRoot = p.join(root.path, 'photos');
    final absolute = p.normalize(p.absolute(filePath));
    if (!p.isWithin(photosRoot, absolute)) {
      throw const FormatException('관리 저장소 밖의 경로');
    }
    return p.posix.joinAll(p.split(p.relative(absolute, from: root.path)));
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(await resolvePath(filePath));
    if (await file.exists()) await file.delete();
  }
}

class _MemoryImagePickerRequestStore implements ImagePickerRequestStore {
  ImagePickerRequestContext? current;

  _MemoryImagePickerRequestStore(this.current);

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

class _TestImagePickerCoordinator extends AppImagePickerCoordinator {
  _TestImagePickerCoordinator({
    required super.picker,
    required super.requestStore,
  });

  void deliverRecovered(List<XFile> files) {
    state = RecoveredImagePickerSelection(
      context: ImagePickerRequestContext.galleryImport(),
      files: files,
    );
  }
}
