import 'dart:async';
import 'dart:io';

import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/core/theme/app_theme.dart';
import 'package:bodymark/features/capture/providers/capture_providers.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/videos/video_camera_screen.dart';
import 'package:bodymark/features/videos/video_providers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bodymark/core/theme/app_tokens.dart';

import 'video_fakes.dart';

final _at = DateTime(2026, 11, 4, 15, 30);

void main() {
  late Directory root;
  late FakeVideoCameraController camera;
  late FakeOrientationLock lock;
  late int settingsOpened;
  late DateTime now;
  RecordedVideo? result;
  late bool popped;
  late GlobalKey<NavigatorState> navigator;
  late List<FakeLessonVideoPlayer> openedPlayers;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('bodymark_video_cam_');
    camera = FakeVideoCameraController(recordedPath: '${root.path}/rec.mp4');
    lock = FakeOrientationLock();
    settingsOpened = 0;
    now = _at;
    result = null;
    popped = false;
    navigator = GlobalKey<NavigatorState>();
    openedPlayers = [];
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoCameraControllerFactoryProvider.overrideWithValue(() => camera),
          screenOrientationLockProvider.overrideWithValue(lock),
          lessonVideoPlayerFactoryProvider.overrideWithValue((path) {
            final player = FakeLessonVideoPlayer(path);
            openedPlayers.add(player);
            return player;
          }),
          openAppSettingsProvider.overrideWithValue(
            () async => settingsOpened++,
          ),
          clockProvider.overrideWithValue(() => now),
          photoStorageServiceProvider.overrideWithValue(
            PhotoStorageServiceImpl(rootPath: '${root.path}/app'),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  result = await Navigator.of(context).push<RecordedVideo>(
                    MaterialPageRoute(
                      builder: (_) => const VideoCameraScreen(),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  Finder key(String id) => find.byKey(ValueKey(id));

  /// 화면 밖에서 실제 파일 I/O가 끝나기를 기다린다.
  Future<void> settleIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  void lifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  testWidgets('녹화 길이는 시작·정지 시각 차이로 재고 녹화본을 돌려준다', (tester) async {
    await pump(tester);
    expect(key(VideoCameraScreen.screenId), findsOneWidget);
    expect(lock.locks, 1);
    expect(key('video.camera.mute.notice'), findsNothing);

    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    expect(camera.startCalls, 1);
    expect(key('video.camera.stop.button'), findsOneWidget);
    // 녹화 중에는 렌즈 전환을 막는다.
    final lens = tester.widget<IconButton>(
      find.descendant(
        of: key('video.camera.lens.button'),
        matching: find.byType(IconButton),
      ),
    );
    expect(lens.onPressed, isNull);

    // 타이머 틱 수와 무관하게 실제 경과(시계)로 표시·기록한다.
    now = _at.add(const Duration(seconds: 65, milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:05'), findsOneWidget);

    await tester.tap(key('video.camera.stop.button'));
    await tester.pumpAndSettle();
    expect(camera.stopCalls, 1);
    await tester.tap(key('video.camera.use.button'));
    await tester.pumpAndSettle();
    expect(result?.path, '${root.path}/rec.mp4');
    expect(result?.duration, const Duration(seconds: 65, milliseconds: 400));
    expect(result?.capturedAt, _at);
    expect(lock.restores, 1);
  });

  testWidgets('미리보기는 화면 폭을 다 쓰고 녹화 뒤 다시 녹화 버튼은 어두운 바탕이다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pump(tester);
    // 카드 안에 가두지 않는다. 세로 화면에서는 미리보기가 화면 폭 전체다.
    expect(tester.getSize(key('video.camera.preview')).width, 360);

    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    await tester.tap(key('video.camera.stop.button'));
    await tester.pumpAndSettle();
    final retake = tester.widget<ButtonStyleButton>(
      find.descendant(
        of: key('video.camera.retake.button'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    final context = tester.element(key('video.camera.retake.button'));
    final background = retake.style?.backgroundColor?.resolve({});
    final foreground = retake.style?.foregroundColor?.resolve({});
    expect(foreground, context.photoColors.onChrome);
    // 테마 기본값(흰 바탕)이면 흰 글자가 보이지 않는다.
    expect(background, context.photoColors.hudSurface);
  });

  testWidgets('녹화를 마치면 카메라 대신 촬영본을 재생해 확인하고, 다시 녹화하면 카메라로 돌아간다', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    await tester.tap(key('video.camera.stop.button'));
    await tester.pumpAndSettle();
    expect(key('video.camera.review'), findsOneWidget);
    expect(key('video.camera.preview'), findsNothing);
    expect(openedPlayers.single.path, '${root.path}/rec.mp4');
    expect(key('video.player.play.button'), findsOneWidget);
    // 확인 재생기는 카메라의 세로 고정을 건드리지 않는다.
    expect(lock.restores, 0);

    await tester.tap(key('video.camera.retake.button'));
    await tester.pumpAndSettle();
    await tester.tap(key('video.camera.discard.confirm.button'));
    await tester.pumpAndSettle();
    expect(key('video.camera.review'), findsNothing);
    expect(key('video.camera.record.button'), findsOneWidget);
    expect(openedPlayers.single.disposed, isTrue);
    expect(lock.restores, 0);
  });

  testWidgets('녹화본이 있는데 닫으면 버리기 확인을 거쳐 임시 파일을 지운다', (tester) async {
    File(camera.recordedPath).writeAsBytesSync([1, 2, 3]);
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    await tester.tap(key('video.camera.stop.button'));
    await tester.pumpAndSettle();

    await tester.tap(key('video.camera.close.button'));
    await tester.pumpAndSettle();
    expect(key('video.camera.discard.dialog'), findsOneWidget);
    await tester.tap(key('video.camera.discard.keep.button'));
    await tester.pumpAndSettle();
    expect(key(VideoCameraScreen.screenId), findsOneWidget);
    expect(File(camera.recordedPath).existsSync(), isTrue);

    await tester.tap(key('video.camera.close.button'));
    await tester.pumpAndSettle();
    await tester.tap(key('video.camera.discard.confirm.button'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
    await settleIo(tester, () => !File(camera.recordedPath).existsSync());
    expect(File(camera.recordedPath).existsSync(), isFalse);
  });

  testWidgets('알림창·권한 창(inactive)은 녹화를 끊지 않고 백그라운드(paused)만 끊는다', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();

    lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.stopCalls, 0);
    expect(camera.disposeCalls, 0);
    expect(key('video.camera.stop.button'), findsOneWidget);

    now = _at.add(const Duration(seconds: 3));
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.paused);
    // 정지 중에는 준비 안내(진행 표시)가 돌기 때문에 settle하지 않는다.
    await tester.pump();
    await tester.pump();
    expect(camera.stopCalls, 1);
    expect(camera.disposeCalls, 1);

    lifecycle(tester, AppLifecycleState.hidden);
    lifecycle(tester, AppLifecycleState.inactive);
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.initializeCalls, 2);
    expect(key('video.camera.use.button'), findsOneWidget);
    expect(find.text('0:03'), findsOneWidget);
  });

  testWidgets('녹화 시작 도중 백그라운드로 가도 시작이 끝나면 정지해 녹화본을 살린다', (tester) async {
    final gate = Completer<void>();
    camera.startGate = gate.future;
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    // 시작 중에는 뒤로가기로 닫히지 않는다(녹화본이 남는 것을 막는다).
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(key(VideoCameraScreen.screenId), findsOneWidget);

    lifecycle(tester, AppLifecycleState.paused);
    await tester.pump();
    expect(camera.stopCalls, 0);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(camera.stopCalls, 1);

    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(key('video.camera.use.button'), findsOneWidget);
  });

  testWidgets('녹화 중 화면이 강제로 닫히면 녹화를 끝내고 파일을 버린다', (tester) async {
    File(camera.recordedPath).writeAsBytesSync([1]);
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();

    // PopScope를 거치지 않는 제거(상위 라우트 교체 등)를 흉내낸다.
    navigator.currentState!.popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    expect(camera.stopCalls, 1);
    await settleIo(tester, () => !File(camera.recordedPath).existsSync());
    expect(File(camera.recordedPath).existsSync(), isFalse);
  });

  testWidgets('마이크가 거부되면 안내하고, 설정을 다녀오기 전에는 다시 묻지 않는다', (tester) async {
    camera.micGranted = false;
    await pump(tester);
    expect(key('video.camera.mute.notice'), findsOneWidget);
    expect(camera.tryAudioCalls, [true]);

    // 렌즈 전환·복귀로 다시 열 때는 마이크를 요청하지 않는다.
    await tester.tap(key('video.camera.lens.button'));
    await tester.pumpAndSettle();
    lifecycle(tester, AppLifecycleState.paused);
    await tester.pump();
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.tryAudioCalls, [true, false, false]);
    expect(key('video.camera.mute.notice'), findsOneWidget);

    // 설정을 다녀오면 한 번 다시 묻는다.
    await tester.tap(key('video.camera.mute.settings.button'));
    await tester.pump();
    expect(settingsOpened, 1);
    camera.micGranted = true;
    lifecycle(tester, AppLifecycleState.paused);
    await tester.pump();
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.tryAudioCalls.last, isTrue);
    expect(key('video.camera.mute.notice'), findsNothing);
  });

  testWidgets('소리 없이도 녹화할 수 있다', (tester) async {
    camera.micGranted = false;
    await pump(tester);
    await tester.tap(key('video.camera.record.button'));
    await tester.pump();
    expect(camera.startCalls, 1);
    await tester.tap(key('video.camera.stop.button'));
    await tester.pumpAndSettle();
    expect(key('video.camera.use.button'), findsOneWidget);
  });

  testWidgets('카메라 권한이 없으면 기존 권한 안내를 보이고 녹화 버튼을 숨긴다', (tester) async {
    camera.initializeError = CameraException('CameraAccessDenied', 'denied');
    await pump(tester);
    expect(key('screen.video.camera.status'), findsOneWidget);
    expect(find.text(keepPhrasesWhole('카메라 권한이 필요해요.')), findsOneWidget);
    expect(key('video.camera.record.button'), findsNothing);

    camera.initializeError = null;
    await tester.tap(key('screen.video.camera.status.retry.button'));
    await tester.pumpAndSettle();
    expect(key('video.camera.record.button'), findsOneWidget);
  });
}
