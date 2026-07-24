import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/capture/capture_review_screen.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
    _FakeBodyPhotoRepository? photoRepo,
    PhotoStorageService? storage,
  }) {
    final container = ProviderContainer(overrides: [
      memberRepositoryProvider.overrideWithValue(memberRepo ?? _FakeMemberRepository(member)),
      photoRecordRepositoryProvider
          .overrideWithValue(recordRepo ?? _FakePhotoRecordRepository()),
      bodyPhotoRepositoryProvider.overrideWithValue(photoRepo ?? _FakeBodyPhotoRepository()),
      photoStorageServiceProvider.overrideWithValue(storage ?? _FakePhotoStorageService()),
    ]);
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  // capture_review_screen은 저장 성공 시 context.goNamed(AppRoutes.captureDirection, ...)로
  // 이동한다. go_router 없이 순수 MaterialApp만 두면 이동 시 예외가 나며 위젯이 settle되지
  // 않으므로, 실제 라우팅과 동일하게 최소 GoRouter로 감싼다.
  Widget wrapWithRouter(ProviderContainer container) {
    final router = GoRouter(
      initialLocation: '/members/$memberId/capture/review',
      routes: [
        GoRoute(
          path: '/members/:${AppParams.memberId}/capture/review',
          name: AppRoutes.captureReview,
          builder: (context, state) => CaptureReviewScreen(
            memberId: state.pathParameters[AppParams.memberId]!,
          ),
        ),
        GoRoute(
          path: '/members/:${AppParams.memberId}/capture',
          name: AppRoutes.captureDirection,
          builder: (context, state) => Scaffold(
            key: const ValueKey('screen.capture.direction.stub'),
            body: const Text('direction stub'),
          ),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('회원 이름과 방향을 표시하고 저장하면 촬영 기록과 사진이 생성된다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final photoRepo = _FakeBodyPhotoRepository();
    final storage = _FakePhotoStorageService();
    final container = buildContainer(recordRepo: recordRepo, photoRepo: photoRepo, storage: storage);
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

    await tester.ensureVisible(find.byKey(const ValueKey('capture.save.button')));
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => recordRepo.records.isNotEmpty);

    expect(recordRepo.records, hasLength(1));
    expect(recordRepo.records.first.memberId, memberId);
    expect(photoRepo.photos, hasLength(1));
    expect(photoRepo.photos.first.direction, BodyDirection.front);
    expect(photoRepo.photos.first.recordId, recordRepo.records.first.id);
    expect(storage.savedFrom, contains(imageFile.path));
  });

  testWidgets('같은 촬영일 기록이 이미 있으면 새로 만들지 않고 사진만 추가한다', (tester) async {
    final recordRepo = _FakePhotoRecordRepository();
    final photoRepo = _FakeBodyPhotoRepository();
    final storage = _FakePhotoStorageService();
    final container = buildContainer(recordRepo: recordRepo, photoRepo: photoRepo, storage: storage);
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

    await tester.ensureVisible(find.byKey(const ValueKey('capture.save.button')));
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => photoRepo.photos.isNotEmpty);

    expect(recordRepo.records, hasLength(1));
    expect(photoRepo.photos, hasLength(1));
    expect(photoRepo.photos.first.recordId, 'r-existing');
  });

  testWidgets('저장 실패 시 실패 상태와 재시도 버튼을 노출한다', (tester) async {
    final container = buildContainer(storage: _FailingPhotoStorageService());
    addTearDown(container.dispose);

    container
        .read(captureSessionProvider(memberId).notifier)
        .setCapturedImage(imageFile.path, gridSettings: GridSettings.defaults);

    await tester.pumpWidget(wrapWithRouter(container));
    await tester.pumpAndSettle();

    const retryKey = ValueKey('screen.capture.review.status.retry.button');
    await tester.ensureVisible(find.byKey(const ValueKey('capture.save.button')));
    await tester.tap(find.byKey(const ValueKey('capture.save.button')));
    await pumpUntil(tester, () => find.byKey(retryKey).evaluate().isNotEmpty);

    expect(find.byKey(retryKey), findsOneWidget);
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
  }) async =>
      [];

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

class _FakeBodyPhotoRepository implements BodyPhotoRepository {
  final List<BodyPhoto> photos = [];

  @override
  Future<void> delete(String id) async {
    photos.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> deleteByRecord(String recordId) async {
    photos.removeWhere((p) => p.recordId == recordId);
  }

  @override
  Future<BodyPhoto?> getById(String id) async {
    for (final photo in photos) {
      if (photo.id == id) return photo;
    }
    return null;
  }

  @override
  Future<void> insert(BodyPhoto photo) async {
    photos.add(photo);
  }

  @override
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async =>
      [];

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async => [];

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async =>
      photos.where((p) => p.recordId == recordId).toList();

  @override
  Future<void> update(BodyPhoto photo) async {
    final index = photos.indexWhere((p) => p.id == photo.id);
    if (index != -1) photos[index] = photo;
  }
}

class _FakePhotoStorageService implements PhotoStorageService {
  final List<String> savedFrom = [];

  @override
  Future<Directory> memberDir(String memberId) async => Directory.systemTemp;

  @override
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  }) async {
    savedFrom.add(sourcePath);
    return sourcePath;
  }

  @override
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  }) async =>
      fileName;

  @override
  Future<void> deleteFile(String filePath) async {}

  @override
  Future<void> deleteMemberDir(String memberId) async {}
}

class _FailingPhotoStorageService implements PhotoStorageService {
  @override
  Future<Directory> memberDir(String memberId) async => Directory.systemTemp;

  @override
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  }) async {
    throw const FileSystemException('저장 실패(테스트)');
  }

  @override
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  }) async {
    throw const FileSystemException('저장 실패(테스트)');
  }

  @override
  Future<void> deleteFile(String filePath) async {}

  @override
  Future<void> deleteMemberDir(String memberId) async {}
}
