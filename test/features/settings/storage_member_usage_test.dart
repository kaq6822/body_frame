import 'dart:io';

import 'package:bodymark/core/database/app_database.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/core/services/video_storage_service.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_repository.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:bodymark/features/settings/services/storage_stats_service.dart';
import 'package:bodymark/features/settings/storage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _mb = 1024 * 1024;

StoredFileUsage _photo(String? member, int bytes) =>
    StoredFileUsage(memberId: member, isVideo: false, bytes: bytes);
StoredFileUsage _video(String? member, int bytes) =>
    StoredFileUsage(memberId: member, isVideo: true, bytes: bytes);

MemberStorageUsage _usage(
  String? id,
  String name,
  int bytes, {
  int photos = 1,
  int videos = 0,
}) => MemberStorageUsage(
  memberId: id,
  name: name,
  photoCount: photos,
  videoCount: videos,
  totalBytes: bytes,
);

void main() {
  group('aggregateMemberStorage', () {
    test('회원별로 개수와 용량을 묶고 큰 순서로 정렬한다', () {
      final result = aggregateMemberStorage(
        [
          _photo('a', 10),
          _video('b', 300),
          _photo('b', 5),
          _photo('a', 20),
          _photo('c', 30),
        ],
        {'a': '김하나', 'b': '이둘', 'c': '박셋'},
      );
      expect(result.map((u) => u.memberId), ['b', 'a', 'c']);
      expect(result.first.photoCount, 1);
      expect(result.first.videoCount, 1);
      expect(result.first.totalBytes, 305);
      expect(result.first.name, '이둘');
      // 용량이 같으면 이름순.
      expect(result[1].name, '김하나');
      expect(result[1].totalBytes, 30);
      expect(result[2].totalBytes, 30);
    });

    test('회원 미연결과 이름을 모르는 회원의 파일은 미연결 묶음으로 모은다', () {
      final result = aggregateMemberStorage(
        [_photo(null, 50), _video('gone', 70), _photo('a', 10)],
        {'a': '김하나'},
      );
      expect(result.first.isUnlinked, isTrue);
      expect(result.first.totalBytes, 120);
      expect(result.first.photoCount, 1);
      expect(result.first.videoCount, 1);
      expect(result.last.memberId, 'a');
    });

    test('미연결 묶음은 용량이 0이면 넣지 않는다', () {
      final result = aggregateMemberStorage(
        [_photo(null, 0), _photo('a', 0)],
        {'a': '김하나'},
      );
      expect(result.map((u) => u.memberId), ['a']);
    });

    test('파일이 없으면 빈 목록이다', () {
      expect(aggregateMemberStorage(const [], {'a': '김하나'}), isEmpty);
    });
  });

  group('StorageStatsServiceImpl', () {
    late Directory root;
    late AppDatabase database;
    late VideoStorageService videos;
    late PhotoStorageService photos;
    late MemberRepository members;
    final at = DateTime(2026, 11, 4, 15);

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bodymark_member_usage_');
      database = AppDatabase.forTesting();
      photos = PhotoStorageServiceImpl(rootPath: root.path);
      videos = VideoStorageServiceImpl(rootPath: root.path);
      members = SqliteMemberRepository(database, photos, videos);
      for (final (id, name) in [('a', '김하나'), ('b', '이둘'), ('c', '박셋')]) {
        await members.save(
          Member(id: id, name: name, createdAt: at, updatedAt: at),
        );
      }
    });

    tearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    Future<void> lessonWithVideo(String member, String id, int bytes) async {
      final src = File(p.join(root.path, '$id.mp4'));
      await src.writeAsBytes(List.filled(bytes, 1), flush: true);
      final path = await videos.saveOriginal(
        capturedAt: at,
        sourcePath: src.path,
      );
      await members.saveLesson(
        PhotoRecord(
          id: 'r$id',
          memberId: member,
          shotAt: at,
          createdAt: at,
          updatedAt: at,
        ),
        const [],
        addedVideos: [
          LessonVideo(
            id: id,
            recordId: 'r$id',
            filePath: path,
            source: LessonVideoSource.camera,
            createdAt: at,
          ),
        ],
      );
    }

    test('디스크의 파일 크기로 회원별 사용량을 큰 순서로 낸다', () async {
      await lessonWithVideo('a', 'v1', 10);
      await lessonWithVideo('b', 'v2', 40);
      await lessonWithVideo('a', 'v3', 5);

      final report = await StorageStatsServiceImpl(
        database: database,
        storage: photos,
        videoStorage: videos,
      ).collect();

      expect(report.byMember.map((u) => u.memberId), ['b', 'a']);
      expect(report.byMember.first.totalBytes, 40);
      expect(report.byMember.last.videoCount, 2);
      expect(report.byMember.last.totalBytes, 15);
      expect(report.byMember.last.name, '김하나');
    });
  });

  group('저장 공간 화면', () {
    StorageUsageReport reportWith(List<MemberStorageUsage> byMember) =>
        StorageUsageReport(
          totalBytes: byMember.fold(0, (s, u) => s + u.totalBytes),
          totalPhotoCount: byMember.fold(0, (s, u) => s + u.photoCount),
          totalVideoCount: byMember.fold(0, (s, u) => s + u.videoCount),
          byMonth: const [],
          byMember: byMember,
        );

    Future<GoRouter> pump(
      WidgetTester tester,
      Future<StorageUsageReport> Function() load, {
      Size size = const Size(360, 800),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const StorageScreen()),
          GoRoute(
            path: '/members/:id',
            builder: (_, s) =>
                Text('member:${s.pathParameters['id']}', key: const Key('m')),
          ),
          GoRoute(
            path: '/all-records',
            builder: (_, s) => Text(
              'records:${s.uri.queryParameters['member']}',
              key: const Key('r'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageUsageProvider.overrideWith((ref) => load())],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    Finder row(String id) => find.byKey(ValueKey('storage.member.item.$id'));

    testWidgets('회원별 사용량을 큰 순서로 보여 주고 미연결 기록도 한 줄로 둔다', (tester) async {
      await pump(
        tester,
        () async => reportWith([
          _usage('b', '이둘', 1200 * _mb, photos: 3, videos: 2),
          _usage(null, '', 300 * _mb, photos: 4),
          _usage('a', '김하나', 600 * _mb, photos: 5),
        ]),
      );

      expect(row('b'), findsOneWidget);
      expect(row('unlinked'), findsOneWidget);
      expect(find.text('회원 미연결 기록'), findsOneWidget);
      expect(find.text('사진 3장 · 동영상 2개'), findsOneWidget);
      expect(find.text('1.17 GB'), findsOneWidget);
      expect(
        tester.getTopLeft(row('b')).dy,
        lessThan(tester.getTopLeft(row('unlinked')).dy),
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('storage.member.bar.a')),
      );
      expect(bar.value, closeTo(0.5, 0.001));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('storage.member.bar.b')),
            )
            .value,
        1.0,
      );
    });

    testWidgets('회원 줄을 누르면 회원 상세를, 미연결 줄은 미연결 기록을 연다', (tester) async {
      final router = await pump(
        tester,
        () async => reportWith([_usage('a', '김하나', 10), _usage(null, '', 5)]),
      );
      await tester.tap(row('a'));
      await tester.pumpAndSettle();
      expect(find.text('member:a'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(row('unlinked'));
      await tester.pumpAndSettle();
      expect(find.text('records:unlinked'), findsOneWidget);
    });

    testWidgets('10명까지만 보이고 전체 보기로 나머지를 펼친다', (tester) async {
      await pump(
        tester,
        () async => reportWith([
          for (var i = 0; i < 12; i++) _usage('m$i', '회원$i', (20 - i) * _mb),
        ]),
      );
      const showAll = ValueKey('storage.members.showAll.button');
      await tester.scrollUntilVisible(find.byKey(showAll), 200);
      await tester.pumpAndSettle();
      expect(row('m9'), findsOneWidget);
      expect(row('m10'), findsNothing);

      await tester.tap(find.byKey(showAll));
      await tester.pumpAndSettle();

      expect(find.byKey(showAll), findsNothing);
      await tester.ensureVisible(row('m11'));
      expect(row('m11'), findsOneWidget);
    });

    testWidgets('기록이 없으면 회원별 빈 상태를 보여 준다', (tester) async {
      await pump(tester, () async => StorageUsageReport.empty);
      expect(
        find.byKey(const ValueKey('storage.members.empty')),
        findsOneWidget,
      );
    });

    testWidgets('불러오기 실패 시 다시 시도하면 다시 읽는다', (tester) async {
      var calls = 0;
      await pump(tester, () async {
        calls++;
        if (calls == 1) throw StateError('읽기 실패');
        return reportWith([_usage('a', '김하나', 10)]);
      });
      expect(find.text('저장 공간 정보를 불러오지 못했어요'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('storage.retry.button')));
      await tester.pumpAndSettle();

      expect(row('a'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('320dp 너비와 2배 글자 크기에서도 넘치지 않는다', (tester) async {
      await pump(
        tester,
        () async => reportWith([
          _usage(
            'a',
            '아주아주긴이름을가진회원님입니다정말로길어요',
            1536 * _mb,
            photos: 1234,
            videos: 567,
          ),
          _usage(null, '', 999 * _mb, photos: 88, videos: 9),
        ]),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(row('a'), findsOneWidget);
      // 용량은 오른쪽 대신 개수 아래 줄로 내려와 이름 칸을 밀어내지 않는다.
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('storage.member.size.a')))
            .dx,
        tester
            .getTopLeft(find.byKey(const ValueKey('storage.member.count.a')))
            .dx,
      );
      await tester.scrollUntilVisible(row('unlinked'), 200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
