import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
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

/// 촬영 결과 확인 화면 위젯 테스트.
///
/// 미리보기/저장 전 회원 이름·방향 재확인/저장 흐름(같은 촬영일 기록에
/// 추가 또는 새 기록 생성)을 검증한다. 실제 리포지토리 대신 ProviderScope
/// override로 인메모리 Fake를 주입한다.
void main() {
  const memberId = 'm1';
  late Member member;
  late Directory tempDir;
  late File imageFile;

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
    final now = DateTime(2026, 1, 1);
    member = Member(id: memberId, name: '홍길동', createdAt: now, updatedAt: now);
    tempDir = await Directory.systemTemp.createTemp('capture_review_test_');
    imageFile = await writeTinyPng(tempDir, 'shot.png');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProviderContainer buildContainer({
    _FakeMemberRepository? memberRepo,
    _FakePhotoRecordRepository? recordRepo,
    _FakePhotoIngestRepository? ingestRepo,
    PhotoStorageService? storage,
  }) {
    final records = recordRepo ?? _FakePhotoRecordRepository();
    final container = ProviderContainer(
      overrides: [
        memberRepositoryProvider.overrideWithValue(
          memberRepo ?? _FakeMemberRepository(member),
        ),
        photoRecordRepositoryProvider.overrideWithValue(records),
        photoIngestRepositoryProvider.overrideWithValue(
          ingestRepo ?? _FakePhotoIngestRepository(records),
        ),
        photoStorageServiceProvider.overrideWithValue(
          storage ?? _FakePhotoStorageService(tempDir),
        ),
      ],
    );
    return container;
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

  // capture_review_screen은 저장 성공 시 context.goNamed(AppRoutes.captureDirection, ...)로
  // 이동한다. go_router 없이 순수 MaterialApp만 두면 이동 시 예외가 나며 위젯이 settle되지
  // 않으므로, 실제 라우팅과 동일하게 최소 GoRouter로 감싼다.
  Widget wrapWithRouter(
    ProviderContainer container, {
    TargetPlatform platform = TargetPlatform.android,
  }) {
    final router = GoRouter(
      initialLocation: '/members/$memberId/capture/review',
      routes: [
        GoRoute(
          path: '/members/:${AppParams.memberId}/capture',
          name: AppRoutes.captureDirection,
          builder: (context, state) => Scaffold(
            key: const ValueKey('screen.capture.direction.stub'),
            body: const Text('direction stub'),
          ),
          routes: [
            GoRoute(
              path: 'review',
              name: AppRoutes.captureReview,
              builder: (context, state) => CaptureReviewScreen(
                memberId: state.pathParameters[AppParams.memberId]!,
              ),
            ),
          ],
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(platform: platform),
        routerConfig: router,
      ),
    );
  }

  testWidgets('회원 이름과 방향을 표시하고 저장하면 촬영 기록과 사진이 생성된다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo);
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
      storage: storage,
    );
    addTearDown(container.dispose);

    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('screen.capture.review')), findsOneWidget);
    // 저장 전 회원 이름 + 촬영 방향 재확인 표시.
    expect(find.textContaining('홍길동'), findsWidgets);
    expect(find.textContaining('정면'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => recordRepo.records.isNotEmpty);

    expect(recordRepo.records, hasLength(1));
    expect(recordRepo.records.first.memberId, memberId);
    expect(ingestRepo.photos, hasLength(1));
    expect(ingestRepo.photos.first.direction, BodyDirection.front);
    expect(ingestRepo.photos.first.recordId, recordRepo.records.first.id);
    expect(ingestRepo.calls, 1);
    expect(storage.savedFrom, contains(imageFile.path));
    await pumpUntil(tester, () => !imageFile.existsSync());
    expect(imageFile.existsSync(), isFalse);
    expect(File(ingestRepo.photos.single.filePath).existsSync(), isTrue);
  });

  testWidgets('같은 촬영일 기록이 이미 있으면 새로 만들지 않고 사진만 추가한다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo);
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
      storage: storage,
    );
    addTearDown(container.dispose);

    final today = DateTime.now();
    final existing = PhotoRecord(
      id: 'r-existing',
      memberId: memberId,
      shotAt: DateTime(today.year, today.month, today.day),
      createdAt: today,
      updatedAt: today,
    );
    recordRepo.records.add(existing);

    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => ingestRepo.photos.isNotEmpty);

    expect(recordRepo.records, hasLength(1));
    expect(ingestRepo.photos, hasLength(1));
    expect(ingestRepo.photos.first.recordId, 'r-existing');
    expect(ingestRepo.lastNewRecords, isEmpty);
  });

  testWidgets('transaction 실패 시 준비 파일을 정리하고 임시 촬영 원본은 재시도용으로 유지한다', (
    tester,
  ) async {
    final recordRepo = _FakePhotoRecordRepository();
    final ingestRepo = _FakePhotoIngestRepository(recordRepo, fail: true);
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(
      recordRepo: recordRepo,
      ingestRepo: ingestRepo,
      storage: storage,
    );
    addTearDown(container.dispose);

    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    const retryKey = ValueKey('screen.capture.review.status.retry.button');
    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.save.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => find.byKey(retryKey).evaluate().isNotEmpty);

    expect(find.byKey(retryKey), findsOneWidget);
    expect(imageFile.existsSync(), isTrue);
    expect(recordRepo.records, isEmpty);
    expect(ingestRepo.photos, isEmpty);
    final managed = Directory(p.join(tempDir.path, 'photos', memberId));
    expect(
      managed.existsSync()
          ? managed.listSync(followLinks: false).whereType<File>()
          : const <File>[],
      isEmpty,
    );
  });

  testWidgets('AppBar 뒤로가기는 임시 원본과 촬영 이미지 세션을 정리한다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(
      captureSessionProvider(memberId),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sessionSubscription.close);
    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => !imageFile.existsSync());

    expect(
      find.byKey(const ValueKey('screen.capture.direction.stub')),
      findsOneWidget,
    );
    expect(imageFile.existsSync(), isFalse);
    expect(
      container.read(captureSessionProvider(memberId)).capturedImagePath,
      isNull,
    );
  });

  testWidgets('Android 시스템 뒤로가기도 임시 원본과 세션을 정리한다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(
      captureSessionProvider(memberId),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sessionSubscription.close);
    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => !imageFile.existsSync());

    expect(
      find.byKey(const ValueKey('screen.capture.direction.stub')),
      findsOneWidget,
    );
    expect(imageFile.existsSync(), isFalse);
    expect(
      container.read(captureSessionProvider(memberId)).capturedImagePath,
      isNull,
    );
  });

  testWidgets('iOS 뒤로가기 스와이프도 임시 원본과 세션을 정리한다', (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final sessionSubscription = container.listen(
      captureSessionProvider(memberId),
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sessionSubscription.close);
    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(
      wrapWithRouter(container, platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(
      const Offset(1, 300),
      const Offset(700, 0),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => !imageFile.existsSync());

    expect(
      find.byKey(const ValueKey('screen.capture.direction.stub')),
      findsOneWidget,
    );
    expect(imageFile.existsSync(), isFalse);
    expect(
      container.read(captureSessionProvider(memberId)).capturedImagePath,
      isNull,
    );
  });

  testWidgets('다시 촬영은 pop callback과 겹쳐도 임시 원본만 정리한다', (tester) async {
    final storage = _FakePhotoStorageService(tempDir);
    final container = buildContainer(storage: storage);
    addTearDown(container.dispose);
    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('capture.retake.button')),
    );
    await tester.tap(find.byKey(const ValueKey('capture.retake.button')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => !imageFile.existsSync());

    expect(
      find.byKey(const ValueKey('screen.capture.direction.stub')),
      findsOneWidget,
    );
    expect(imageFile.existsSync(), isFalse);
    expect(storage.savedFrom, isEmpty);
  });
}

class _FakeMemberRepository implements MemberRepository {
  final Member member;

  _FakeMemberRepository(this.member);

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Member?> getById(String id) async => id == member.id ? member : null;

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
  Future<List<PhotoRecord>> listByMember(String memberId) async =>
      records.where((r) => r.memberId == memberId).toList();

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
    required String memberId,
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
  final Directory root;
  final List<String> savedFrom = [];

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
    savedFrom.add(sourcePath);
    final directory = await memberDir(memberId);
    final saved = await File(
      sourcePath,
    ).copy(p.join(directory.path, fileName ?? p.basename(sourcePath)));
    return saved.path;
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
  Future<void> deleteFile(String filePath) async {
    final resolved = await resolvePath(filePath);
    final file = File(resolved);
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
}
