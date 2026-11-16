import 'dart:async';
import 'dart:io';

import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/repositories/lesson_video_repository.dart';
import 'package:bodymark/core/repositories/photo_record_repository.dart';
import 'package:bodymark/core/router/app_routes.dart';
import 'package:bodymark/core/services/app_image_picker.dart';
import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/core/services/video_storage_service.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/core/theme/app_tokens.dart';
import 'package:bodymark/features/members/lesson_detail_screen.dart';
import 'package:bodymark/features/members/lesson_editor_screen.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/members/member_repository.dart';
import 'package:bodymark/features/home/home_screen.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:bodymark/features/records/services/photo_export_sink.dart';
import 'package:bodymark/features/videos/lesson_video_tile.dart';
import 'package:bodymark/features/videos/video_player_screen.dart';
import 'package:bodymark/features/videos/video_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'video_fakes.dart';

final _at = DateTime(2026, 11, 4, 15);
final _member = Member(id: 'm1', name: '김서연', createdAt: _at, updatedAt: _at);

class _RecordingMembers implements MemberRepository {
  final saved = <(PhotoRecord, List<BodyPhoto>, List<LessonVideo>)>[];
  bool failNext = false;
  @override
  Future<void> saveLesson(
    PhotoRecord record,
    List<BodyPhoto> addedPhotos, {
    List<LessonVideo> addedVideos = const [],
  }) async {
    if (failNext) throw StateError('저장 실패');
    saved.add((record, addedPhotos, addedVideos));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 복사 경로만 기록하는 동영상 저장소. 무변형 복사는 서비스 단위 테스트가 본다.
class _FakeVideoStorage implements VideoStorageService {
  final copied = <String>[];
  final deleted = <String>[];
  @override
  Future<String> saveOriginal({
    required DateTime capturedAt,
    required String sourcePath,
  }) async {
    copied.add(sourcePath);
    return '/app/videos/202611/v${copied.length}.mp4';
  }

  @override
  Future<void> deleteFile(String filePath) async => deleted.add(filePath);
  @override
  Future<String> resolvePath(String storedPath) async => storedPath;
  @override
  Future<String> toStoredPath(String filePath) async => filePath;
}

class _FakeVideoRepo implements LessonVideoRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String id) async => deleted.add(id);
  @override
  Future<LessonVideo?> getById(String id) async => null;
  @override
  Future<List<LessonVideo>> listAll() async => const [];
  @override
  Future<List<LessonVideo>> listByRecord(String recordId) async => const [];
}

class _FakeRecords implements PhotoRecordRepository {
  final deleted = <String>[];
  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShare implements PhotoExportSink {
  final shared = <String>[];
  @override
  Future<void> shareOriginalFile(
    String sourcePath, {
    Rect? sharePositionOrigin,
  }) async => shared.add(sourcePath);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder key(String id) => find.byKey(ValueKey(id));

/// 저장 전 동영상 줄의 식별자(uuid 기반)를 화면 순서대로 돌려준다.
List<String> pendingIds(WidgetTester tester) => tester
    .widgetList<LessonVideoTile>(
      find.byType(LessonVideoTile, skipOffstage: false),
    )
    .where((w) => w.pending)
    .map((w) => w.identifier)
    .toList();

/// 지연 생성되는 ListView 아래쪽 위젯을 화면에 올린다.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  required List<RouteBase> routes,
  required String push,
  double textScale = 1,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      ...routes,
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _at),
        membersProvider.overrideWith((ref) async => [_member]),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  router.push(push);
  await tester.pumpAndSettle();
  return router;
}

LessonVideo _video(String id, {String recordId = 'r1'}) => LessonVideo(
  id: id,
  recordId: recordId,
  filePath: '/app/videos/202611/$id.mp4',
  phase: 'after',
  durationMs: 65000,
  sizeBytes: 3 * 1024 * 1024,
  source: LessonVideoSource.camera,
  createdAt: _at,
);

void main() {
  group('레슨 편집', () {
    late _RecordingMembers members;
    late _FakeVideoStorage storage;
    late FakeVideoPicker picker;
    late _FakeVideoRepo videoRepo;
    late List<String> cleaned;
    late _FakeRecords records;

    setUp(() {
      cleaned = [];
      records = _FakeRecords();
      members = _RecordingMembers();
      storage = _FakeVideoStorage();
      picker = FakeVideoPicker(videoPath: '/picker/cache/gallery.mov');
      videoRepo = _FakeVideoRepo();
    });

    List<Override> editorOverrides({
      List<LessonVideo> saved = const [],
      String? memo = '기존 메모',
      Future<List<LessonVideo>> Function()? savedFuture,
      ImagePickerRequestStore? requestStore,
    }) => [
      pickerCopyCleanerProvider.overrideWithValue(
        (path) async => cleaned.add(path),
      ),
      photoRecordRepositoryProvider.overrideWithValue(records),
      memberRepositoryProvider.overrideWithValue(members),
      videoStorageServiceProvider.overrideWithValue(storage),
      lessonVideoRepositoryProvider.overrideWithValue(videoRepo),
      appImagePickerProvider.overrideWithValue(picker),
      imagePickerRequestStoreProvider.overrideWithValue(
        requestStore ?? MemoryRequestStore(),
      ),
      videoDurationProbeProvider.overrideWithValue(
        (path) async => const Duration(seconds: 90),
      ),
      videoFileSizeProvider.overrideWithValue((path) async => 2 * 1024 * 1024),
      recordProvider.overrideWith(
        (ref, id) async => PhotoRecord(
          id: id,
          memberId: 'm1',
          shotAt: _at,
          memo: memo,
          createdAt: _at,
          updatedAt: _at,
        ),
      ),
      recordPhotosProvider.overrideWith((ref, id) async => const []),
      recordVideosProvider.overrideWith(
        (ref, id) => savedFuture?.call() ?? Future.value(saved),
      ),
    ];

    final routes = <RouteBase>[
      GoRoute(
        path: '/new',
        builder: (_, _) => const LessonEditorScreen(memberId: 'm1'),
      ),
      GoRoute(
        path: '/edit',
        builder: (_, _) =>
            const LessonEditorScreen(memberId: 'm1', recordId: 'r1'),
      ),
      // 실제 촬영 화면은 따로 검증한다. 여기서는 녹화본을 돌려주는 대역만 둔다.
      GoRoute(
        path: '/video-camera',
        builder: (context, _) => Scaffold(
          body: TextButton(
            key: const ValueKey('stub.recorded'),
            onPressed: () => Navigator.of(context).pop(
              RecordedVideo(
                path: '/cache/rec.mp4',
                duration: const Duration(seconds: 42),
                capturedAt: _at.add(const Duration(minutes: 3)),
              ),
            ),
            child: const Text('done'),
          ),
        ),
      ),
      GoRoute(
        path: '/lessons/:recordId/videos/:videoId',
        builder: (_, s) => const Scaffold(body: Text('player')),
      ),
      GoRoute(
        path: '/members/:id',
        builder: (_, s) =>
            Scaffold(body: Text('member ${s.pathParameters['id']}')),
      ),
    ];

    testWidgets('촬영·선택한 동영상을 목록에 보이고 동영상만으로 저장한다', (tester) async {
      await _pump(
        tester,
        overrides: editorOverrides(),
        routes: routes,
        push: '/new',
      );
      await reveal(tester, key('lessons.video.record.button'));
      expect(key('lessons.video.section'), findsOneWidget);

      await tester.ensureVisible(key('lessons.video.record.button'));
      await tester.tap(key('lessons.video.record.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('stub.recorded'));
      await tester.pumpAndSettle();
      expect(pendingIds(tester), hasLength(1));
      expect(
        pendingIds(tester).single,
        matches(RegExp(r'^lessons\.video\.pending\.[0-9a-f-]{36}\.tile$')),
      );
      expect(find.textContaining('0:42 · 2.0 MB · 촬영'), findsOneWidget);
      expect(key('lessons.video.count'), findsOneWidget);

      await reveal(tester, key('lessons.video.pick.button'));
      await tester.tap(key('lessons.video.pick.button'));
      await tester.pumpAndSettle();
      expect(picker.videoCalls, 1);
      expect(pendingIds(tester), hasLength(2));
      expect(find.textContaining('1:30 · 2.0 MB · 갤러리'), findsOneWidget);
      expect(find.text('총 2개'), findsOneWidget);

      await tester.tap(key('lessons.save.button'));
      await tester.pumpAndSettle();

      expect(storage.copied, ['/cache/rec.mp4', '/picker/cache/gallery.mov']);
      final (record, photos, videos) = members.saved.single;
      expect(photos, isEmpty);
      expect(videos.map((v) => v.filePath), [
        '/app/videos/202611/v1.mp4',
        '/app/videos/202611/v2.mp4',
      ]);
      expect(videos.every((v) => v.recordId == record.id), isTrue);
      expect(videos.first.source, LessonVideoSource.camera);
      expect(videos.first.durationMs, 42000);
      expect(videos.first.capturedAt, _at.add(const Duration(minutes: 3)));
      expect(videos.first.phase, 'before');
      expect(videos.last.source, LessonVideoSource.gallery);
      expect(videos.last.durationMs, 90000);
      expect(videos.last.sizeBytes, 2 * 1024 * 1024);
      expect(find.text('home'), findsOneWidget);
      // 저장 뒤 picker 사본은 정리한다(관리 저장소에 이미 복사됐다).
      expect(cleaned, ['/picker/cache/gallery.mov']);
    });

    testWidgets('저장 전 동영상은 확인 후 목록에서 뺀다', (tester) async {
      await _pump(
        tester,
        overrides: editorOverrides(),
        routes: routes,
        push: '/new',
      );
      await reveal(tester, key('lessons.video.pick.button'));
      await tester.tap(key('lessons.video.pick.button'));
      await tester.pumpAndSettle();

      final id = pendingIds(tester).single;
      await tester.tap(key('$id.remove.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.cancel.button'));
      await tester.pumpAndSettle();
      expect(pendingIds(tester), [id]);
      expect(cleaned, isEmpty);

      await tester.tap(key('$id.remove.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.accept.button'));
      await tester.pumpAndSettle();
      expect(pendingIds(tester), isEmpty);
      // 갤러리 사본은 빼는 즉시 정리를 요청한다(임시 디렉터리 안인지는 정리 함수가 본다).
      expect(cleaned, ['/picker/cache/gallery.mov']);

      // 남은 입력이 없으면 저장하지 않는다.
      await tester.tap(key('lessons.save.button'));
      await tester.pumpAndSettle();
      expect(members.saved, isEmpty);
      expect(key('lessons.save.error'), findsOneWidget);
    });

    testWidgets('저장된 동영상 삭제는 확인을 거쳐 리포지토리로 지운다', (tester) async {
      await _pump(
        tester,
        overrides: editorOverrides(saved: [_video('v1')]),
        routes: routes,
        push: '/edit',
      );
      final tile = key('lessons.video.existing.v1.tile.remove.button');
      await reveal(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(key('common.confirm.dialog'), findsOneWidget);
      await tester.tap(key('common.confirm.accept.button'));
      await tester.pumpAndSettle();
      expect(videoRepo.deleted, ['v1']);
    });

    testWidgets('편집 화면은 320dp·2배 글꼴에서 동영상 카드가 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        overrides: editorOverrides(saved: [_video('v1')]),
        routes: routes,
        push: '/edit',
        textScale: 2,
      );
      await reveal(tester, key('lessons.video.pick.button'));
      await tester.tap(key('lessons.video.pick.button'));
      await tester.pumpAndSettle();
      await reveal(tester, key(pendingIds(tester).single));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('동영상 카드의 촬영·선택 버튼은 사진 카드처럼 1:1로 꽉 찬다', (tester) async {
      await _pump(
        tester,
        overrides: editorOverrides(),
        routes: routes,
        push: '/new',
      );
      await reveal(tester, key('lessons.video.pick.button'));
      final record = tester.getRect(key('lessons.video.record.button'));
      final pick = tester.getRect(key('lessons.video.pick.button'));
      final photoCapture = tester.getRect(key('lessons.capture.button'));
      final photoImport = tester.getRect(key('lessons.import.button'));
      expect(record.width, closeTo(pick.width, 1));
      expect(record.left, closeTo(photoCapture.left, 1));
      expect(pick.right, closeTo(photoImport.right, 1));
    });

    testWidgets('저장하지 않고 나가면 카메라 녹화본과 picker 사본을 정리한다', (tester) async {
      final temp = Directory.systemTemp.createTempSync('bodymark_rec_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final recording = File('${temp.path}/rec.mp4')..writeAsBytesSync([1]);
      await _pump(
        tester,
        overrides: [
          ...editorOverrides(),
          photoStorageServiceProvider.overrideWithValue(
            PhotoStorageServiceImpl(rootPath: '${temp.path}/app'),
          ),
        ],
        routes: [
          ...routes.where((r) => (r as GoRoute).path != '/video-camera'),
          GoRoute(
            path: '/video-camera',
            builder: (context, _) => Scaffold(
              body: TextButton(
                key: const ValueKey('stub.recorded'),
                onPressed: () => Navigator.of(context).pop(
                  RecordedVideo(
                    path: recording.path,
                    duration: const Duration(seconds: 5),
                    capturedAt: _at,
                  ),
                ),
                child: const Text('done'),
              ),
            ),
          ),
        ],
        push: '/new',
      );
      await reveal(tester, key('lessons.video.record.button'));
      await tester.tap(key('lessons.video.record.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('stub.recorded'));
      await tester.pumpAndSettle();
      await tester.tap(key('lessons.video.pick.button'));
      await tester.pumpAndSettle();
      expect(pendingIds(tester), hasLength(2));

      // 시스템 뒤로가기: 작성 중이므로 버릴지 묻는다.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.accept.button'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(members.saved, isEmpty);
      expect(cleaned, ['/picker/cache/gallery.mov']);
      for (var i = 0; i < 50 && recording.existsSync(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(recording.existsSync(), isFalse);
    });

    testWidgets('레슨 저장이 실패하면 미리 복사한 동영상을 되돌리고 입력을 남긴다', (tester) async {
      members.failNext = true;
      await _pump(
        tester,
        overrides: editorOverrides(),
        routes: routes,
        push: '/new',
      );
      await reveal(tester, key('lessons.video.pick.button'));
      await tester.tap(key('lessons.video.pick.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('lessons.save.button'));
      await tester.pumpAndSettle();

      expect(storage.copied, ['/picker/cache/gallery.mov']);
      expect(storage.deleted, ['/app/videos/202611/v1.mp4']);
      expect(key('lessons.save.error'), findsOneWidget);
      expect(pendingIds(tester), hasLength(1));
      expect(cleaned, isEmpty);
    });

    testWidgets('선택 중 앱이 종료된 동영상은 같은 회원 편집에서 붙이고 확인 처리한다', (tester) async {
      picker.lostVideoPath = '/picker/cache/lost.mp4';
      final store = MemoryRequestStore()
        ..value = ImagePickerRequestContext.lessonVideo(memberId: 'm1');
      await _pump(
        tester,
        overrides: editorOverrides(requestStore: store),
        routes: routes,
        push: '/new',
      );
      await reveal(tester, key('lessons.video.section'));
      expect(pendingIds(tester), hasLength(1));
      expect(find.textContaining('1:30 · 2.0 MB · 갤러리'), findsOneWidget);
      expect(store.value, isNull);
      final container = ProviderScope.containerOf(
        tester.element(key('lessons.video.section')),
      );
      expect(container.read(appImagePickerCoordinatorProvider), isNull);
    });

    testWidgets('동영상만 남은 레슨의 마지막 동영상은 레슨 삭제를 제안한다', (tester) async {
      await _pump(
        tester,
        overrides: editorOverrides(saved: [_video('v1')], memo: null),
        routes: routes,
        push: '/edit',
      );
      final remove = key('lessons.video.existing.v1.tile.remove.button');
      await reveal(tester, remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('마지막 동영상이에요'), findsOneWidget);
      await tester.tap(key('common.confirm.cancel.button'));
      await tester.pumpAndSettle();
      expect(records.deleted, isEmpty);
      expect(videoRepo.deleted, isEmpty);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.accept.button'));
      await tester.pumpAndSettle();
      expect(records.deleted, ['r1']);
      expect(videoRepo.deleted, isEmpty);
      expect(find.text('member m1'), findsOneWidget);
    });

    testWidgets('저장된 동영상을 아직 못 읽었으면 빈 레슨으로 판단하지 않는다', (tester) async {
      final pendingVideos = Completer<List<LessonVideo>>();
      await _pump(
        tester,
        overrides: editorOverrides(
          memo: null,
          savedFuture: () => pendingVideos.future,
        ),
        routes: routes,
        push: '/edit',
      );
      await tester.tap(key('lessons.save.button'));
      await tester.pump();
      expect(key('lessons.save.error'), findsNothing);
      expect(members.saved, hasLength(1));
      pendingVideos.complete(const []);
      await tester.pumpAndSettle();
    });
  });

  group('레슨 상세와 재생', () {
    late List<FakeLessonVideoPlayer> players;
    late bool failNext;
    late _FakeVideoRepo videoRepo;
    late _FakeShare share;

    setUp(() {
      players = [];
      failNext = false;
      videoRepo = _FakeVideoRepo();
      share = _FakeShare();
    });

    List<Override> detailOverrides({
      Future<List<LessonVideo>> Function()? videos,
    }) => [
      recordProvider.overrideWith(
        (ref, id) async => PhotoRecord(
          id: id,
          memberId: 'm1',
          shotAt: _at,
          memo: '메모',
          createdAt: _at,
          updatedAt: _at,
        ),
      ),
      recordPhotosProvider.overrideWith((ref, id) async => const []),
      recordVideosProvider.overrideWith(
        (ref, id) => videos?.call() ?? Future.value([_video('v1')]),
      ),
      timelineProvider.overrideWith((ref) async => const []),
      lessonVideoRepositoryProvider.overrideWithValue(videoRepo),
      photoExportSinkProvider.overrideWithValue(share),
      lessonVideoPlayerFactoryProvider.overrideWithValue((path) {
        final player = FakeLessonVideoPlayer(path, fail: failNext);
        players.add(player);
        return player;
      }),
    ];

    final routes = <RouteBase>[
      GoRoute(
        path: '/lessons/:recordId',
        builder: (_, s) =>
            LessonDetailScreen(recordId: s.pathParameters['recordId']!),
      ),
      GoRoute(
        path: '/lessons/:recordId/videos/:videoId',
        name: AppRoutes.videoPlayer,
        builder: (_, s) => LessonVideoPlayerScreen(
          recordId: s.pathParameters[AppParams.recordId]!,
          videoId: s.pathParameters[AppParams.videoId]!,
        ),
      ),
    ];

    testWidgets('상세의 동영상 영역에서 재생 화면으로 들어가 재생·일시정지한다', (tester) async {
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1',
      );
      await reveal(tester, key('lessons.video.v1.button'));
      expect(find.text('동영상 (1개)'), findsOneWidget);
      await tester.tap(key('lessons.video.v1.button'));
      await tester.pumpAndSettle();

      expect(key(LessonVideoPlayerScreen.screenId), findsOneWidget);
      expect(players.single.path, '/app/videos/202611/v1.mp4');
      expect(find.text('0:00 / 1:05'), findsOneWidget);
      await tester.tap(key('video.player.play.button'));
      await tester.pump();
      expect(players.single.isPlaying, isTrue);
      await tester.tap(key('video.player.play.button'));
      await tester.pump();
      expect(players.single.isPlaying, isFalse);

      await tester.tap(key('video.player.share.button'));
      await tester.pump();
      expect(share.shared, ['/app/videos/202611/v1.mp4']);
    });

    testWidgets('재생에 실패하면 안내와 다시 시도를 보이고 재시도로 연다', (tester) async {
      failNext = true;
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1/videos/v1',
      );
      expect(key('video.player.status'), findsOneWidget);
      expect(key('video.player.play.button'), findsNothing);
      expect(players.single.disposed, isTrue);

      failNext = false;
      await tester.tap(key('video.player.retry.button'));
      await tester.pumpAndSettle();
      expect(players, hasLength(2));
      expect(key('video.player.play.button'), findsOneWidget);
    });

    testWidgets('재생 화면의 삭제는 확인을 거쳐 지우고 상세로 돌아간다', (tester) async {
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1/videos/v1',
      );
      await tester.tap(key('video.player.delete.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.cancel.button'));
      await tester.pumpAndSettle();
      expect(videoRepo.deleted, isEmpty);

      await tester.tap(key('video.player.delete.button'));
      await tester.pumpAndSettle();
      await tester.tap(key('common.confirm.accept.button'));
      await tester.pumpAndSettle();
      expect(videoRepo.deleted, ['v1']);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('재생 화면 앱바 제목과 아이콘은 어두운 바탕용 밝은 색이다', (tester) async {
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1/videos/v1',
      );
      final title = find.text('수업 후 동영상');
      expect(title, findsOneWidget);
      expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
      final style = DefaultTextStyle.of(tester.element(title)).style;
      expect(style.color, const AppPhotoColors().onChrome);
      final shareIcon = tester.widget<Icon>(
        find.descendant(
          of: key('video.player.share.button'),
          matching: find.byType(Icon),
        ),
      );
      expect(
        IconTheme.of(tester.element(find.byWidget(shareIcon))).color,
        const AppPhotoColors().onChrome,
      );
    });

    testWidgets('삭제 확인과 공유 전에는 재생을 멈춘다', (tester) async {
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1/videos/v1',
      );
      await tester.tap(key('video.player.play.button'));
      await tester.pump();
      expect(players.single.isPlaying, isTrue);
      await tester.tap(key('video.player.delete.button'));
      await tester.pumpAndSettle();
      expect(players.single.isPlaying, isFalse);
      await tester.tap(key('common.confirm.cancel.button'));
      await tester.pumpAndSettle();

      await tester.tap(key('video.player.play.button'));
      await tester.pump();
      await tester.tap(key('video.player.share.button'));
      await tester.pump();
      expect(players.single.isPlaying, isFalse);
      expect(share.shared, hasLength(1));
    });

    testWidgets('동영상 수를 아직 모르면 레슨 삭제 확인에 "동영상 포함"으로 알린다', (tester) async {
      await _pump(
        tester,
        overrides: [
          // 동영상 조회 실패: 개수를 모른다.
          ...detailOverrides(videos: () => Future.error(StateError('조회 실패'))),
        ],
        routes: routes,
        push: '/lessons/r1',
      );
      await reveal(tester, key('lessons.delete.button'));
      expect(key('lessons.video.error'), findsOneWidget);
      await tester.tap(key('lessons.delete.button'));
      await tester.pumpAndSettle();
      expect(find.textContaining('일지(동영상 포함)이 함께 삭제돼요'), findsOneWidget);
    });

    testWidgets('동영상 수를 알면 레슨 삭제 확인에 개수를 알린다', (tester) async {
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1',
      );
      await reveal(tester, key('lessons.delete.button'));
      await tester.tap(key('lessons.delete.button'));
      await tester.pumpAndSettle();
      expect(find.textContaining('일지와 동영상 1개가 함께 삭제돼요'), findsOneWidget);
    });

    testWidgets('가로 화면에서도 재생 화면이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        overrides: detailOverrides(),
        routes: routes,
        push: '/lessons/r1/videos/v1',
        textScale: 2,
      );
      expect(key('video.player.view'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('복구 배너', () {
    Future<(MemoryRequestStore, List<String>)> pumpMembers(
      WidgetTester tester, {
      String memberId = 'm1',
      String? recordId,
    }) async {
      final store = MemoryRequestStore()
        ..value = ImagePickerRequestContext.lessonVideo(
          memberId: memberId,
          recordId: recordId,
        );
      final cleaned = <String>[];
      await _pump(
        tester,
        overrides: [
          appImagePickerProvider.overrideWithValue(
            FakeVideoPicker(lostVideoPath: '/picker/cache/lost.mp4'),
          ),
          imagePickerRequestStoreProvider.overrideWithValue(store),
          pickerCopyCleanerProvider.overrideWithValue(
            (path) async => cleaned.add(path),
          ),
          timelineProvider.overrideWith((ref) async => const []),
          unlinkedRecordCountProvider.overrideWith((ref) async => 0),
        ],
        routes: [
          // 복구 배너는 앱을 다시 열면 보이는 홈 한 곳에만 있다.
          GoRoute(path: '/start', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/members/:id/lessons/new',
            builder: (_, s) =>
                Scaffold(body: Text('new ${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/members/:id/lessons/:rid/edit',
            builder: (_, s) => Scaffold(
              body: Text(
                'edit ${s.pathParameters['id']} ${s.pathParameters['rid']}',
              ),
            ),
          ),
        ],
        push: '/start',
      );
      return (store, cleaned);
    }

    testWidgets('복구된 동영상 선택은 회원 이름과 함께 알리고 그 회원의 새 레슨을 연다', (tester) async {
      await pumpMembers(tester);
      expect(key('members.recoveredVideo.banner'), findsOneWidget);
      expect(
        find.textContaining(keepPhrasesWhole('김서연 회원의 레슨에 붙일 수 있어요')),
        findsOneWidget,
      );
      await tester.tap(key('members.recoveredVideo.open.button'));
      await tester.pumpAndSettle();
      expect(find.text('new m1'), findsOneWidget);
    });

    testWidgets('기존 레슨에서 시작한 선택은 그 레슨 편집을 연다', (tester) async {
      await pumpMembers(tester, recordId: 'r9');
      await tester.tap(key('members.recoveredVideo.open.button'));
      await tester.pumpAndSettle();
      expect(find.text('edit m1 r9'), findsOneWidget);
    });

    testWidgets('버리기는 복구 결과를 확인 처리하고 picker 사본을 정리한다', (tester) async {
      final (store, cleaned) = await pumpMembers(tester, memberId: 'gone');
      expect(key('members.recoveredVideo.open.button'), findsNothing);
      await tester.tap(key('members.recoveredVideo.discard.button'));
      await tester.pumpAndSettle();
      expect(key('members.recoveredVideo.banner'), findsNothing);
      expect(store.value, isNull);
      expect(cleaned, ['/picker/cache/lost.mp4']);
    });
  });

  test('레슨 동영상 picker 문맥은 회원·레슨을 구분해 직렬화된다', () {
    final context = ImagePickerRequestContext.lessonVideo(
      memberId: 'm1',
      recordId: 'r1',
    );
    final restored = ImagePickerRequestContext.fromJson(context.toJson());
    expect(restored, context);
    expect(
      restored,
      isNot(ImagePickerRequestContext.lessonVideo(memberId: 'm2')),
    );
    expect(
      () => ImagePickerRequestContext.fromJson({
        'operation': 'lessonVideo',
        'photoId': 'p',
      }),
      throwsFormatException,
    );
  });
}
