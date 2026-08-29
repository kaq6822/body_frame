import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/photo_ingest_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/capture/capture_review_screen.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// 연속 촬영 결과 일괄 확인 화면 위젯 테스트.
///
/// 여러 컷을 하나의 촬영 기록으로 저장하는 흐름, 같은 촬영일 기록 재사용,
/// 실패 시 준비 파일 정리를 검증한다. 실제 리포지토리 대신 ProviderScope
/// override로 인메모리 Fake를 주입한다.
void main() {
  late Directory tempDir;
  late File frontFile;
  late File backFile;

  Future<File> writeTinyPng(Directory dir, String name) async {
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
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    return file;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('capture_review_test_');
    frontFile = await writeTinyPng(tempDir, 'front.png');
    backFile = await writeTinyPng(tempDir, 'back.png');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer buildContainer({
    _FakePhotoRecordRepository? recordRepo,
    _FakePhotoIngestRepository? ingestRepo,
    PhotoStorageService? storage,
  }) {
    final records = recordRepo ?? _FakePhotoRecordRepository();
    return ProviderContainer(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(
          ingestRepo ?? _FakePhotoIngestRepository(records),
        ),
        photoStorageServiceProvider.overrideWithValue(
          storage ?? _FakePhotoStorageService(tempDir),
        ),
      ],
    );
  }

  /// 세션에 촬영 결과를 채워 넣는다. 인덱스는 [kSessionDirections] 순서다.
  void captureShots(ProviderContainer container, Map<int, String> paths) {
    final notifier = container.read(captureSessionProvider.notifier);
    for (final entry in paths.entries) {
      notifier.goTo(entry.key);
      notifier.captureCurrent(entry.value, gridSettings: GridSettings.defaults);
    }
  }

  // 저장 과정은 실제 파일 IO(dart:io)와 이미지 디코드(dart:ui)를 거치므로
  // pumpAndSettle()로는 감지할 수 없다(진행 중 스피너는 무한 애니메이션이라
  // pumpAndSettle이 타임아웃한다). 조건이 참이 될 때까지 실제 시간을 조금씩
  // 흐르게 하며 pump를 반복한다.
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

  // capture_review_screen은 저장 성공 시 context.go('/')로 홈에 돌아간다.
  // go_router 없이 순수 MaterialApp만 두면 이동 시 예외가 나며 위젯이
  // settle되지 않으므로, 실제 라우팅과 동일하게 최소 GoRouter로 감싼다.
  // 홈이 촬영 화면이므로 리뷰는 홈의 직접 하위 라우트다.
  Widget wrapWithRouter(ProviderContainer container) {
    final router = GoRouter(
      initialLocation: '/review',
      routes: [
        GoRoute(
          path: '/',
          name: AppRoutes.home,
          builder: (context, state) => const Scaffold(
            key: ValueKey('screen.capture.camera.stub'),
            body: Text('camera stub'),
          ),
          routes: [
            GoRoute(
              path: 'review',
              name: AppRoutes.captureReview,
              builder: (context, state) => const CaptureReviewScreen(),
            ),
          ],
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('여러 컷을 하나의 촬영 기록으로 한 번에 저장한다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo);
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
      storage: storage,
    );
    addTearDown(container.dispose);

    captureShots(container, {0: frontFile.path, 3: backFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('screen.capture.review')), findsOneWidget);
    expect(find.text('2장 촬영됨'), findsOneWidget);
    // 찍은 컷과 건너뛴 컷을 모두 보여준다.
    expect(
      find.byKey(const ValueKey('capture.review.shot.front')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('capture.review.shot.leftSide')),
      findsOneWidget,
    );
    // 찍은 컷은 촬영 당시 격자와 함께 보여준다. 건너뛴 컷에는 얹을 사진이 없다.
    expect(
      find.byKey(const ValueKey('capture.review.shot.front.grid.overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('capture.review.shot.leftSide.grid.overlay')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => ingestRepo.photos.isNotEmpty);

    expect(ingestRepo.calls, 1);
    expect(ingestRepo.lastNewRecords, hasLength(1));
    expect(ingestRepo.photos, hasLength(2));
    // 두 사진 모두 같은 기록에 속한다.
    final recordIds = ingestRepo.photos.map((p) => p.recordId).toSet();
    expect(recordIds, hasLength(1));
    expect(recordIds.single, ingestRepo.lastNewRecords.single.id);
    expect(
      ingestRepo.photos.map((p) => p.direction),
      containsAll([BodyDirection.front, BodyDirection.back]),
    );
    expect(storage.savedFrom, containsAll([frontFile.path, backFile.path]));
  });

  testWidgets('라벨과 메모를 입력하면 기록에 함께 저장된다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
    );
    addTearDown(container.dispose);

    captureShots(container, {0: frontFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('capture.review.label.field')),
      '동생',
    );
    await tester.enterText(
      find.byKey(const ValueKey('capture.review.memo.field')),
      '체중 감량 시작',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => ingestRepo.photos.isNotEmpty);

    final record = ingestRepo.lastNewRecords.single;
    expect(record.label, '동생');
    expect(record.memo, '체중 감량 시작');
  });

  testWidgets('입력한 라벨과 메모는 세션에 남아 다시 촬영 후에도 유지된다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    captureShots(container, {0: frontFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('capture.review.label.field')),
      '동생',
    );
    await tester.enterText(
      find.byKey(const ValueKey('capture.review.memo.field')),
      '체중 감량 시작',
    );
    await tester.pumpAndSettle();

    // 다시 촬영은 이 화면을 닫는다. 입력이 세션에 없으면 돌아올 때 사라진다.
    final session = container.read(captureSessionProvider);
    expect(session.label, '동생');
    expect(session.memo, '체중 감량 시작');
  });

  testWidgets('촬영일이 같은 기록이 이미 있어도 이 촬영은 별개의 기록으로 저장한다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
    );
    addTearDown(container.dispose);

    final today = DateTime.now();
    recordRepo.records.add(
      PhotoRecord(
        id: 'r-existing',
        shotAt: DateTime(today.year, today.month, today.day),
        createdAt: today,
        updatedAt: today,
      ),
    );

    captureShots(container, {0: frontFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => ingestRepo.photos.isNotEmpty);

    // 촬영 한 건이 기록 하나다. 같은 날 기록에 합치면 촬영 횟수가 사라진다.
    expect(ingestRepo.lastNewRecords, hasLength(1));
    expect(ingestRepo.lastNewRecords.single.id, isNot('r-existing'));
    expect(
      ingestRepo.photos.single.recordId,
      ingestRepo.lastNewRecords.single.id,
    );
  });

  testWidgets('transaction 실패 시 준비 파일을 정리하고 재시도할 수 있다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo, fail: true);
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
      storage: storage,
    );
    addTearDown(container.dispose);

    captureShots(container, {0: frontFile.path, 3: backFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    const retryKey = ValueKey('screen.capture.review.status.retry.button');
    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => find.byKey(retryKey).evaluate().isNotEmpty);

    expect(find.byKey(retryKey), findsOneWidget);
    // 임시 촬영 원본은 재시도를 위해 남긴다.
    expect(frontFile.existsSync(), isTrue);
    expect(backFile.existsSync(), isTrue);
    expect(ingestRepo.photos, isEmpty);
    // 앱 저장소에 준비했던 파일은 모두 정리한다.
    final managed = Directory(p.join(tempDir.path, 'photos'));
    expect(
      managed.existsSync()
          ? managed
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
          : const <File>[],
      isEmpty,
    );
  });

  testWidgets('다시 촬영을 누르면 해당 컷을 비우고 카메라로 돌아간다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(
      captureSessionProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    captureShots(container, {0: frontFile.path});

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.review.retake.front')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.review.retake.front')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => !frontFile.existsSync());

    expect(
      find.byKey(const ValueKey('screen.capture.camera.stub')),
      findsOneWidget,
    );
    final session = container.read(captureSessionProvider);
    expect(session.shots.first.isCaptured, isFalse);
    expect(session.currentIndex, 0);
    expect(frontFile.existsSync(), isFalse);
  });

  testWidgets('촬영 결과가 없으면 안내 문구만 보여준다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    expect(find.text('확인할 촬영 결과가 없습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture.save.button')), findsNothing);
  });
}

class _FakePhotoRecordRepository implements PhotoRecordRepository {
  final List<PhotoRecord> records = [];

  @override
  Future<void> delete(String id) async {
    records.removeWhere((r) => r.id == id);
  }

  @override
  Future<PhotoRecord?> getById(String id) async {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<void> insert(PhotoRecord record) async {
    records.add(record);
  }

  @override
  Future<List<PhotoRecord>> listAll() async => List.of(records);

  @override
  Future<void> update(PhotoRecord record) async {
    final index = records.indexWhere((r) => r.id == record.id);
    if (index != -1) records[index] = record;
  }
}

class _FakePhotoIngestRepository implements PhotoIngestRepository {
  final _FakePhotoRecordRepository records;
  final List<BodyPhoto> photos = [];
  final bool fail;
  int calls = 0;
  List<PhotoRecord> lastNewRecords = const [];

  _FakePhotoIngestRepository(this.records, {this.fail = false});

  @override
  Future<void> insertPrepared({
    required List<PhotoRecord> newRecords,
    required List<BodyPhoto> photos,
  }) async {
    calls += 1;
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
  final List<String> savedFrom = [];

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
    final saved = await File(
      sourcePath,
    ).copy(p.join(directory.path, fileName ?? p.basename(sourcePath)));
    return saved.path;
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
  Future<void> deleteFile(String filePath) async {
    final resolved = await resolvePath(filePath);
    final file = File(resolved);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> resolvePath(String storedPath) async {
    if (p.isAbsolute(storedPath)) return storedPath;
    return p.join(root.path, storedPath);
  }

  @override
  Future<String> toStoredPath(String filePath) async {
    final photosRoot = p.join(root.path, 'photos');
    if (!p.isWithin(photosRoot, filePath)) {
      throw const FormatException('앱 사진 저장소 밖의 경로입니다.');
    }
    return p.posix.joinAll(p.split(p.relative(filePath, from: root.path)));
  }
}
