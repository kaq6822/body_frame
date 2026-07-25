import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
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
      ImagePickerRequestContext.galleryImport('m1'),
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
          memberRepositoryProvider.overrideWithValue(_FakeMemberRepository()),
        ],
        child: const MaterialApp(home: GalleryImportScreen(memberId: 'm1')),
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

  testWidgets('다른 회원의 갤러리 화면은 유실 결과를 소비하지 않는다', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
      'ASsJTYQAAAAASUVORK5CYII=',
    );
    final picker = _FakeAppImagePicker(
      LostDataResponse(
        files: [XFile.fromData(bytes, path: recoveredImage.path)],
      ),
    );
    final expected = ImagePickerRequestContext.galleryImport('m1');
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: _MemoryImagePickerRequestStore(expected),
    );
    await coordinator.initialize();
    final container = ProviderContainer(
      overrides: [
        appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        memberRepositoryProvider.overrideWithValue(_FakeMemberRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GalleryImportScreen(
            key: ValueKey('wrong-gallery-screen'),
            memberId: 'm2',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('capture.import.item.0.card')),
      findsNothing,
    );
    expect(coordinator.state?.context, expected);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GalleryImportScreen(
            key: ValueKey('matching-gallery-screen'),
            memberId: 'm1',
          ),
        ),
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

    expect(
      find.byKey(const ValueKey('capture.import.item.0.card')),
      findsOneWidget,
    );
    // 복구는 목록만 채운다. 방향 지정과 사용자의 저장 조작 전에는 등록할 수 없다.
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('capture.import.save.button')),
    );
    expect(saveButton.onPressed, isNull);
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
        memberRepositoryProvider.overrideWithValue(_FakeMemberRepository()),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingest),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GalleryImportScreen(memberId: 'm1')),
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
        memberRepositoryProvider.overrideWithValue(_FakeMemberRepository()),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(ingest),
        photoStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GalleryImportScreen(memberId: 'm1')),
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
    final managed = Directory(p.join(tempDir.path, 'photos', 'm1'));
    expect(
      managed.existsSync()
          ? managed.listSync(followLinks: false).whereType<File>()
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

class _FakeMemberRepository implements MemberRepository {
  Member _member(String id) => Member(
    id: id,
    name: '테스트 회원',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Member?> getById(String id) async =>
      id == 'm1' || id == 'm2' ? _member(id) : null;

  @override
  Future<void> insert(Member member) async {}

  @override
  Future<List<MemberListItem>> list({
    String? query,
    MemberSort sort = MemberSort.recentShot,
  }) async => [];

  @override
  Future<void> update(Member member) async {}
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
  Future<List<PhotoRecord>> listByMember(String memberId) async =>
      records.where((record) => record.memberId == memberId).toList();

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
    required String memberId,
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
  final Directory root;

  _FakePhotoStorageService(this.root);

  @override
  Future<void> reconcilePendingQuarantines() async {}

  @override
  Future<Directory> memberDir(String memberId) async {
    final directory = Directory(p.join(root.path, 'photos', memberId));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  }) async {
    final directory = await memberDir(memberId);
    return (await File(
      sourcePath,
    ).copy(p.join(directory.path, fileName ?? p.basename(sourcePath)))).path;
  }

  @override
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final directory = await memberDir(memberId);
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

  @override
  Future<void> deleteMemberDir(String memberId) async {}

  @override
  Future<StorageQuarantine?> quarantineFile(String filePath) async => null;

  @override
  Future<StorageQuarantine?> quarantineMemberDir(String memberId) async => null;

  @override
  Future<void> restoreQuarantine(StorageQuarantine quarantine) async {}

  @override
  Future<void> discardQuarantine(StorageQuarantine quarantine) async {}
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
