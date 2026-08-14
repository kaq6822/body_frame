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
}

class _FakeAppImagePicker implements AppImagePicker {
  final LostDataResponse response;
  final List<XFile> pickedFiles;
  @override
  final bool supportsLostDataRecovery;
  int retrieveLostDataCalls = 0;

  _FakeAppImagePicker(
    this.response, {
    this.pickedFiles = const [],
    this.supportsLostDataRecovery = true,
  });

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;

  @override
  Future<List<XFile>> pickMultiImage() async => pickedFiles;

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
    final directory = await bucketDir(shotAt);
    return (await File(
      sourcePath,
    ).copy(p.join(directory.path, fileName ?? p.basename(sourcePath)))).path;
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
