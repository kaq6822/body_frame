import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/korean_text.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/photo_frame.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/features/capture/camera_permission_guide.dart';
import 'package:body_frame/features/capture/grid_camera_screen.dart';
import 'package:body_frame/features/capture/providers/capture_providers.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:body_frame/features/records/providers/records_providers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_capture_camera.dart';

/// 홈(연속 세션 촬영) 화면 위젯 테스트.
///
/// `camera` 패키지는 실기기 하드웨어에 의존하므로 [FakeCaptureCameraController]를
/// ProviderScope override로 주입해 초기화 성공/실패, 방향 자동 전환, 셀프 타이머
/// 카운트다운, 렌즈 전환, 마지막 컷 이후 리뷰 이동을 실기기 없이 검증한다.
void main() {
  late Directory tempDir;
  late File frontGuideFile;
  late File sideGuideFile;

  setUp(() async {
    // GridSettingsServiceImpl이 내부에서 사용하는 shared_preferences 목 초기화.
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('body_frame_camera_guide_');
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
      'ASsJTYQAAAAASUVORK5CYII=',
    );
    frontGuideFile = File('${tempDir.path}/front.png');
    sideGuideFile = File('${tempDir.path}/left_side.png');
    await frontGuideFile.writeAsBytes(imageBytes);
    await sideGuideFile.writeAsBytes(imageBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildApp(
    FakeCaptureCameraController Function() factory, {
    Future<String?> Function(BodyDirection direction)? loadPreviousGuide,
    List<RecordWithPhotos> timeline = const [],
  }) {
    final guideLoader = loadPreviousGuide ?? (_) async => null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: AppRoutes.home,
          builder: (context, state) => const GridCameraScreen(),
          routes: [
            GoRoute(
              path: 'review',
              name: AppRoutes.captureReview,
              builder: (context, state) => const Scaffold(
                key: ValueKey('screen.capture.review.stub'),
                body: Text('review stub'),
              ),
            ),
            GoRoute(
              path: 'records',
              name: AppRoutes.records,
              builder: (context, state) => const Scaffold(
                key: ValueKey('screen.records.stub'),
                body: Text('records stub'),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          name: AppRoutes.settings,
          builder: (context, state) => const Scaffold(
            key: ValueKey('screen.settings.stub'),
            body: Text('settings stub'),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        captureCameraControllerFactoryProvider.overrideWithValue(factory),
        previousPhotoGuidePathProvider.overrideWith(
          (ref, direction) => guideLoader(direction),
        ),
        // 하단 기록 썸네일이 읽는 타임라인. override하지 않으면 실제 sqflite
        // 리포지토리로 내려가 위젯 테스트에서 결과가 결정론적이지 않다.
        timelineProvider.overrideWith((ref) async => timeline),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  CaptureSessionState sessionOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GridCameraScreen)),
    );
    return container.read(captureSessionProvider);
  }

  /// 격자·이전 사진 가이드·전체 설정 링크는 모두 빠른 설정 패널 안에 있다.
  Future<void> openQuickPanel(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('capture.grid.settings.button')),
    );
    await tester.pumpAndSettle();
  }

  /// 패널은 뷰파인더를 절반만 덮으므로 아래쪽 항목은 스크롤해야 보인다.
  Future<void> revealInQuickPanel(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  /// 흔한 1080x2400 @2.75(≈393dp) 화면. 기본 테스트 뷰포트(800x600)는 실기기보다
  /// 넓어 상단·하단 바 오버플로를 놓친다.
  void useNarrowPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  testWidgets('실기기 폭에서 진행 칩 4개가 넘치지 않고 모두 보인다', (tester) async {
    useNarrowPhoneViewport(tester);

    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    // 오버플로는 렌더 예외로 보고된다.
    expect(tester.takeException(), isNull);
    for (final direction in kSessionDirections) {
      expect(
        find.byKey(ValueKey('capture.progress.step.${direction.key}')),
        findsOneWidget,
        reason: '${direction.label} 칩이 상단바에서 잘렸습니다.',
      );
    }
  });

  testWidgets('실기기 폭에서 하단 바 4개 요소가 넘치지 않고 모두 보인다', (tester) async {
    useNarrowPhoneViewport(tester);

    // 렌즈 버튼까지 상단 바에 들어간 상태에서 검증한다.
    await tester.pumpWidget(
      buildApp(() => FakeCaptureCameraController(canSwitchLens: true)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final id in const [
      'capture.records.button',
      'capture.skip.button',
      'capture.shutter.button',
      'capture.finish.button',
    ]) {
      expect(
        find.byKey(ValueKey(id)),
        findsOneWidget,
        reason: '$id 이(가) 없습니다.',
      );
    }
  });

  testWidgets('홈이므로 뒤로가기 버튼 대신 빠른 설정 토글을 둔다', (tester) async {
    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('capture.camera.back.button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('capture.grid.settings.button')),
      findsOneWidget,
    );
  });

  testWidgets('셔터를 누르면 화면을 벗어나지 않고 다음 방향으로 넘어간다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(GridCameraScreen.screenId)),
      findsOneWidget,
    );
    expect(sessionOf(tester).current.direction, BodyDirection.front);
    expect(find.textContaining('1 / 4 · 정면'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 1);
    // 리뷰로 넘어가지 않고 같은 화면에서 다음 방향으로 전환된다.
    expect(
      find.byKey(const ValueKey('screen.capture.review.stub')),
      findsNothing,
    );
    final session = sessionOf(tester);
    expect(session.current.direction, BodyDirection.leftSide);
    expect(session.shots.first.imagePath, fake.capturedPath);
    expect(session.capturedCount, 1);
    expect(find.textContaining('2 / 4 · 좌측면'), findsOneWidget);
  });

  testWidgets('마지막 방향까지 찍으면 리뷰 화면으로 이동한다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    for (var i = 0; i < kSessionDirections.length; i++) {
      await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
      await tester.pumpAndSettle();
    }

    expect(fake.takePictureCalls, kSessionDirections.length);
    expect(
      find.byKey(const ValueKey('screen.capture.review.stub')),
      findsOneWidget,
    );
  });

  testWidgets('건너뛴 방향은 촬영하지 않고 다음 단계로 넘어간다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.skip.button')));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 0);
    final session = sessionOf(tester);
    expect(session.current.direction, BodyDirection.leftSide);
    expect(session.shots.first.isCaptured, isFalse);
  });

  testWidgets('진행 칩을 탭하면 해당 방향으로 되돌아가 재촬영할 수 있다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();
    expect(sessionOf(tester).current.direction, BodyDirection.leftSide);

    await tester.tap(find.byKey(const ValueKey('capture.progress.step.front')));
    await tester.pumpAndSettle();

    expect(sessionOf(tester).current.direction, BodyDirection.front);
  });

  testWidgets('찍은 컷이 없으면 완료 버튼이 비활성이고 한 장이라도 있으면 활성이다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    final finishButton = find.byKey(const ValueKey('capture.finish.button'));
    expect(tester.widget<TextButton>(finishButton).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(finishButton).onPressed, isNotNull);

    await tester.tap(finishButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('screen.capture.review.stub')),
      findsOneWidget,
    );
  });

  testWidgets('카메라 초기화 실패 시 재시도와 기록 보기 대체 동선을 노출한다', (tester) async {
    final fake = FakeCaptureCameraController(initializeShouldFail: true);
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('screen.capture.camera.status.retry.button')),
      findsOneWidget,
    );

    final fallback = find.byKey(
      const ValueKey('capture.camera.records.fallback.button'),
    );
    expect(fallback, findsOneWidget);

    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.records.stub')), findsOneWidget);
  });

  group('카메라 권한 거부', () {
    /// 실기기 권한 거부에서 확인된 문제를 고정한다.
    ///
    /// 권한 창이 뜨고 닫힐 때마다 lifecycle이 흔들리는데, 복귀마다 초기화를 다시
    /// 걸어 거부된 권한을 향해 무한히 재시도했다. 그동안 실패를 화면에 반영하지
    /// 못해 사용자는 "카메라를 준비하는 중입니다."만 계속 보았다.
    FakeCaptureCameraController deniedCamera() => FakeCaptureCameraController(
      initializeError: CameraException(
        'CameraAccessDenied',
        'Camera access permission was denied.',
      ),
    );

    testWidgets('준비 중 대신 권한 안내를 보여준다', (tester) async {
      final fake = deniedCamera();
      await tester.pumpWidget(buildApp(() => fake));
      await tester.pumpAndSettle();

      expect(
        find.text(keepPhrasesWhole('카메라 권한이 필요합니다.')),
        findsOneWidget,
      );
      expect(
        find.text(keepPhrasesWhole('카메라를 준비하는 중입니다.')),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier('screen.capture.camera.status'))
            .value,
        'failure',
      );
    });

    testWidgets('앱이 재개될 때마다 초기화를 다시 시도하지 않는다', (tester) async {
      final fake = deniedCamera();
      await tester.pumpWidget(buildApp(() => fake));
      await tester.pumpAndSettle();
      expect(fake.initializeCalls, 1);

      // 권한 창이 오가는 상황. 이 왕복마다 재시도하면 무한 루프가 된다.
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }

      expect(fake.initializeCalls, 1);
      // 안내가 사라지면 사용자가 무엇을 해야 할지 알 수 없다.
      expect(
        find.text(keepPhrasesWhole('카메라 권한이 필요합니다.')),
        findsOneWidget,
      );
    });

    testWidgets('설정 열기를 누르면 시스템 설정 화면 열기를 요청한다', (tester) async {
      var openCalls = 0;
      final fake = deniedCamera();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            openAppSettingsProvider.overrideWithValue(() async {
              openCalls += 1;
            }),
          ],
          child: buildApp(() => fake),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('screen.capture.camera.status.settings.button'),
        ),
      );
      await tester.pumpAndSettle();

      expect(openCalls, 1);
      // 설정을 열어도 카메라를 다시 여는 것은 사용자가 돌아와 재시도할 때다.
      expect(fake.initializeCalls, 1);
    });

    testWidgets('설정 열기가 실패해도 안내와 경로가 그대로 남는다', (tester) async {
      final fake = deniedCamera();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            openAppSettingsProvider.overrideWithValue(
              () async => throw StateError('설정을 열 수 없음(테스트)'),
            ),
          ],
          child: buildApp(() => fake),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('screen.capture.camera.status.settings.button'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(keepPhrasesWhole('카메라 권한이 필요합니다.')),
        findsOneWidget,
      );
      // 버튼이 막힌 기기에서 직접 찾아갈 수 있어야 한다. 화면과 같은 함수로
      // 경로를 만들어 실행 중인 플랫폼 분기까지 함께 확인한다.
      expect(
        find.text(joinBreadcrumb(cameraPermissionSettingsPath())),
        findsOneWidget,
      );
    });

    testWidgets('권한을 허용하고 재시도를 누르면 미리보기로 복구된다', (tester) async {
      final fake = deniedCamera();
      await tester.pumpWidget(buildApp(() => fake));
      await tester.pumpAndSettle();

      fake.initializeError = null;
      await tester.tap(
        find.byKey(const ValueKey('screen.capture.camera.status.retry.button')),
      );
      await tester.pumpAndSettle();

      expect(fake.initializeCalls, 2);
      expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
      expect(
        find.text(keepPhrasesWhole('카메라 권한이 필요합니다.')),
        findsNothing,
      );
    });
  });

  testWidgets('기록 썸네일은 최근 기록의 정면 사진과 건수 배지를 보여준다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        FakeCaptureCameraController.new,
        timeline: [
          RecordWithPhotos(
            record: _record('r-latest', DateTime(2026, 3, 2)),
            photos: [
              _photo(
                id: 'p-side',
                recordId: 'r-latest',
                path: sideGuideFile.path,
                direction: BodyDirection.leftSide,
              ),
              _photo(
                id: 'p-front',
                recordId: 'r-latest',
                path: frontGuideFile.path,
                direction: BodyDirection.front,
              ),
            ],
          ),
          RecordWithPhotos(
            record: _record('r-old', DateTime(2026, 2, 1)),
            photos: const [],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final thumbnail = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('capture.records.button')),
        matching: find.byType(Image),
      ),
    );
    expect((thumbnail.image as ResizeImage).imageProvider, isA<FileImage>());
    expect(
      ((thumbnail.image as ResizeImage).imageProvider as FileImage).file.path,
      frontGuideFile.path,
    );
    // 기록 건수 배지.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture.records.button')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('capture.records.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.records.stub')), findsOneWidget);
  });

  testWidgets('기록이 없으면 썸네일 대신 아이콘만 보여준다', (tester) async {
    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture.records.button')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('capture.records.button')),
        matching: find.byIcon(Icons.photo_library_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('빠른 설정 패널에 격자·이전 사진 가이드·전체 설정 링크가 함께 있다', (tester) async {
    await tester.pumpWidget(
      buildApp(
        FakeCaptureCameraController.new,
        loadPreviousGuide: (_) async => frontGuideFile.path,
      ),
    );
    await tester.pumpAndSettle();

    // 닫힌 기본 상태에서는 패널 컨트롤이 보이지 않는다.
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.toggle'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('capture.settings.link')), findsNothing);

    await openQuickPanel(tester);

    expect(find.byKey(const ValueKey('capture.quick.panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('capture.grid.toggle')), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.toggle'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.opacity.slider'),
      findsOneWidget,
    );

    final settingsLink = find.byKey(const ValueKey('capture.settings.link'));
    await revealInQuickPanel(tester, settingsLink);
    await tester.tap(settingsLink);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.settings.stub')), findsOneWidget);
  });

  testWidgets('최근 사진을 원본 비율의 반투명 가이드로 표시하고 설정을 바꾼다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(
      buildApp(() => fake, loadPreviousGuide: (_) async => frontGuideFile.path),
    );
    await tester.pumpAndSettle();

    // 가이드 이미지는 뷰파인더 레이어라 패널과 무관하게 보인다.
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsOneWidget,
    );

    await openQuickPanel(tester);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.toggle'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.opacity.slider'),
      findsOneWidget,
    );

    final imageFinder = find.byKey(
      ValueKey('capture.previousGuide.image.${frontGuideFile.path}'),
    );
    final image = tester.widget<Image>(imageFinder);
    expect(image.fit, BoxFit.contain);
    expect((image.image as FileImage).file.path, frontGuideFile.path);

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.bySemanticsIdentifier('capture.previousGuide.image'),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.35);

    final toggleFinder = find.byKey(
      const ValueKey('capture.previousGuide.toggle'),
    );
    await revealInQuickPanel(tester, toggleFinder);
    await tester.tap(toggleFinder);
    await tester.pump();
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsNothing,
    );

    await tester.tap(toggleFinder);
    await tester.pump();
    final sliderFinder = find.byKey(
      const ValueKey('capture.previousGuide.opacity.slider'),
    );
    await revealInQuickPanel(tester, sliderFinder);
    final before = tester.widget<Slider>(sliderFinder).value;
    await tester.drag(sliderFinder, const Offset(100, 0));
    await tester.pump();
    final after = tester.widget<Slider>(sliderFinder).value;
    expect(after, greaterThan(before));
    expect(after, lessThanOrEqualTo(0.7));
  });

  testWidgets('단계가 넘어가면 해당 방향의 가이드로 교체한다', (tester) async {
    final requested = <BodyDirection>[];
    await tester.pumpWidget(
      buildApp(
        FakeCaptureCameraController.new,
        loadPreviousGuide: (direction) async {
          requested.add(direction);
          return direction == BodyDirection.front
              ? frontGuideFile.path
              : sideGuideFile.path;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requested.last, BodyDirection.front);
    expect(
      find.byKey(
        ValueKey('capture.previousGuide.image.${frontGuideFile.path}'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('capture.skip.button')));
    await tester.pumpAndSettle();

    expect(requested.last, BodyDirection.leftSide);
    expect(
      find.byKey(ValueKey('capture.previousGuide.image.${sideGuideFile.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('capture.previousGuide.image.${frontGuideFile.path}'),
      ),
      findsNothing,
    );
  });

  testWidgets('사용할 이전 파일이 없어도 카메라 촬영은 계속 사용할 수 있다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await openQuickPanel(tester);

    expect(find.text('표시할 이전 사진이 없습니다.'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('capture.previousGuide.toggle')),
          )
          .onChanged,
      isNull,
    );
    expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
  });

  testWidgets('이전 사진 조회에 실패해도 카메라 촬영은 계속 사용할 수 있다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(
      buildApp(
        () => fake,
        loadPreviousGuide: (_) async => throw StateError('이전 사진 조회 실패(테스트)'),
      ),
    );
    await tester.pumpAndSettle();

    await openQuickPanel(tester);

    expect(find.text('이전 사진을 불러오지 못했습니다.'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
  });

  group('촬영 프레임', () {
    /// 실기기 세로 화면(1080x2400 @2.75 ≈ 393x873dp)을 재현한다. 기본 테스트
    /// 뷰포트(800x600)는 가로로 넓어 세로 프레임 검증에 맞지 않는다.
    void usePortraitPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
    }

    Future<Rect> frameRect(WidgetTester tester, double sensorAspect) async {
      await tester.pumpWidget(
        buildApp(() => FakeCaptureCameraController(sensorAspect: sensorAspect)),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(const ValueKey('capture.frame')));
    }

    testWidgets('센서 비율이 달라도 프레임은 항상 3:4다', (tester) async {
      usePortraitPhone(tester);

      // 16:9(에뮬레이터·720p 실기기), 4:3(흔한 센서), 1:1(정사각).
      for (final sensorAspect in [16 / 9, 4 / 3, 1.0]) {
        final rect = await frameRect(tester, sensorAspect);
        expect(
          rect.width / rect.height,
          closeTo(kPhotoFrameAspect, 0.001),
          reason: '센서 $sensorAspect 에서 프레임 비율이 어긋났습니다.',
        );
      }
    });

    testWidgets('센서 비율이 달라도 프레임 크기와 격자 위치가 같다', (tester) async {
      usePortraitPhone(tester);

      final rects = <Rect>[];
      final gridRects = <Rect>[];
      for (final sensorAspect in [16 / 9, 4 / 3, 1.0]) {
        rects.add(await frameRect(tester, sensorAspect));
        gridRects.add(
          tester.getRect(find.byKey(const ValueKey('capture.grid.overlay'))),
        );
      }

      // 격자는 부모 박스 기준으로 그려지므로, 프레임이 흔들리면 촬영할 때 맞춘
      // 격자와 비교 화면의 격자가 몸 대비 다른 자리에 놓인다.
      expect(rects[1], rects[0]);
      expect(rects[2], rects[0]);
      expect(gridRects[0], rects[0]);
      expect(gridRects[1], rects[0]);
      expect(gridRects[2], rects[0]);
    });

    testWidgets('미리보기는 프레임 안에 letterbox되어 잘리지 않는다', (tester) async {
      usePortraitPhone(tester);

      // 16:9 센서를 세로로 들면 9:16(0.5625)이라 3:4 프레임보다 좁고 길다.
      final frame = await frameRect(tester, 16 / 9);
      final preview = tester.getRect(
        find.byKey(const ValueKey('fake.camera.preview')),
      );

      // 화각을 잘라내지 않으므로 미리보기가 프레임을 넘지 않는다.
      expect(preview.width, lessThanOrEqualTo(frame.width + 0.001));
      expect(preview.height, lessThanOrEqualTo(frame.height + 0.001));
      // 세로가 더 긴 센서라 높이를 채우고 좌우에 여백이 남는다.
      expect(preview.height, closeTo(frame.height, 0.001));
      expect(preview.width, lessThan(frame.width));
      expect(preview.width / preview.height, closeTo(9 / 16, 0.001));
    });

    testWidgets('센서가 3:4면 여백 없이 프레임을 가득 채운다', (tester) async {
      usePortraitPhone(tester);

      final frame = await frameRect(tester, 4 / 3);
      final preview = tester.getRect(
        find.byKey(const ValueKey('fake.camera.preview')),
      );

      expect(preview.width, closeTo(frame.width, 0.001));
      expect(preview.height, closeTo(frame.height, 0.001));
    });

    testWidgets('좁은 화면에서도 프레임이 넘치지 않는다', (tester) async {
      usePortraitPhone(tester);

      final frame = await frameRect(tester, 16 / 9);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      expect(tester.takeException(), isNull);
      expect(frame.width, lessThanOrEqualTo(screen.width + 0.001));
      expect(frame.height, lessThanOrEqualTo(screen.height + 0.001));
    });
  });

  testWidgets('빠른 설정이 열려 있으면 시스템 뒤로가기가 패널만 닫는다', (tester) async {
    // 이 화면이 홈이라 뒤로가기는 앱을 닫는다. 패널을 열어 둔 채 뒤로가기를
    // 눌렀을 때 앱이 종료되면 안 된다.
    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('capture.grid.settings.button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture.quick.panel')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('capture.quick.panel')), findsNothing);
    expect(
      find.byKey(const ValueKey(GridCameraScreen.screenId)),
      findsOneWidget,
    );
  });

  testWidgets('카운트다운 중 시스템 뒤로가기는 카운트다운만 취소한다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    // 끔 → 3초.
    await tester.tap(find.byKey(const ValueKey('capture.timer.button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('capture.countdown')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('capture.countdown')), findsNothing);
    expect(
      find.byKey(const ValueKey(GridCameraScreen.screenId)),
      findsOneWidget,
    );
    // 취소했으므로 촬영은 일어나지 않는다.
    expect(fake.takePictureCalls, 0);
  });

  testWidgets('설정의 셀프 타이머 기본값이 세션 시작값이 된다', (tester) async {
    // 설정 화면에서 5초를 골라 둔 상태를 재현한다.
    SharedPreferences.setMockInitialValues({
      'app_settings': const AppSettings(
        capture: CaptureOptions(timerSeconds: 5),
      ).toJson(),
    });

    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('capture.timer.button'))
          .value,
      '5초',
    );
  });

  testWidgets('타이머 버튼은 끔 → 3 → 5 → 10 → 끔으로 순환한다', (tester) async {
    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    final timerButton = find.byKey(const ValueKey('capture.timer.button'));
    String? valueOf() => tester
        .getSemantics(find.bySemanticsIdentifier('capture.timer.button'))
        .value;

    expect(valueOf(), '끔');
    for (final expected in const ['3초', '5초', '10초', '끔']) {
      await tester.tap(timerButton);
      await tester.pump();
      expect(valueOf(), expected);
    }
  });

  testWidgets('타이머가 켜지면 셔터가 카운트다운을 시작하고 0초에 촬영한다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    // 끔 → 3초.
    await tester.tap(find.byKey(const ValueKey('capture.timer.button')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pump();

    final countdown = find.byKey(const ValueKey('capture.countdown'));
    // 남은 초는 기록 건수 배지와 겹칠 수 있으므로 오버레이 안에서 찾는다.
    Finder remainingText(String seconds) =>
        find.descendant(of: countdown, matching: find.text(seconds));

    expect(countdown, findsOneWidget);
    expect(remainingText('3'), findsOneWidget);
    expect(find.text('화면을 탭하면 취소됩니다'), findsOneWidget);
    // 카운트다운 중에는 건너뛰기·완료를 누를 수 없다.
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('capture.skip.button')))
          .onPressed,
      isNull,
    );
    expect(fake.takePictureCalls, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(remainingText('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(remainingText('1'), findsOneWidget);
    expect(fake.takePictureCalls, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 1);
    expect(countdown, findsNothing);
    // 다음 방향으로 넘어가도 타이머 값은 유지된다.
    expect(sessionOf(tester).current.direction, BodyDirection.leftSide);
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('capture.timer.button'))
          .value,
      '3초',
    );
  });

  testWidgets('카운트다운 오버레이를 탭하면 취소되고 촬영하지 않는다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.timer.button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pump();

    final countdown = find.byKey(const ValueKey('capture.countdown'));
    expect(countdown, findsOneWidget);

    await tester.tap(countdown);
    await tester.pump();

    expect(countdown, findsNothing);

    // 취소 후에는 원래 시간이 지나도 촬영이 일어나지 않는다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(fake.takePictureCalls, 0);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('capture.skip.button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('카운트다운 중 화면을 벗어나도 타이머가 남지 않는다', (tester) async {
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.timer.button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('capture.countdown')), findsOneWidget);

    // 화면을 완전히 버린다. Timer가 남아 있으면 pump에서 예외가 보고된다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));

    expect(tester.takeException(), isNull);
    expect(fake.takePictureCalls, 0);
  });

  testWidgets('앱이 백그라운드로 가면 카운트다운을 취소한다', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.timer.button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('capture.countdown')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(find.byKey(const ValueKey('capture.countdown')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(fake.takePictureCalls, 0);
  });

  testWidgets('전환 불가 기기에서는 렌즈 버튼을 렌더하지 않는다', (tester) async {
    await tester.pumpWidget(buildApp(FakeCaptureCameraController.new));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('capture.lens.button')), findsNothing);
  });

  testWidgets('렌즈 버튼을 탭하면 전면 카메라로 재초기화한다', (tester) async {
    final fake = FakeCaptureCameraController(canSwitchLens: true);
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    final lensButton = find.byKey(const ValueKey('capture.lens.button'));
    expect(lensButton, findsOneWidget);
    expect(fake.requestedFrontLens, [false]);

    await tester.tap(lensButton);
    await tester.pumpAndSettle();

    expect(fake.requestedFrontLens, [false, true]);
    expect(fake.isFrontLens, isTrue);
    expect(fake.disposeCalls, 0);
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('capture.lens.button'))
          .value,
      '전면',
    );

    // 다시 누르면 후면으로 되돌린다.
    await tester.tap(lensButton);
    await tester.pumpAndSettle();
    expect(fake.requestedFrontLens, [false, true, false]);
    expect(fake.isFrontLens, isFalse);
    expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
  });

  testWidgets('앱이 비활성화되면 카메라를 해제하고 복귀 시 다시 초기화한다', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final fake = FakeCaptureCameraController();
    await tester.pumpWidget(
      buildApp(() => fake, loadPreviousGuide: (_) async => frontGuideFile.path),
    );
    await tester.pumpAndSettle();

    expect(fake.initializeCalls, 1);
    expect(fake.disposeCalls, 0);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump();
    expect(fake.disposeCalls, 1);
    expect(fake.isInitialized, isFalse);

    // inactive -> paused처럼 연속 상태가 전달돼도 중복 해제하지 않는다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fake.disposeCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fake.initializeCalls, 2);
    expect(fake.isInitialized, isTrue);
    expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsOneWidget,
    );
  });

  test('가이드 provider는 유실된 최신 파일을 건너뛰고 다음 정상 파일을 반환한다', () async {
    final missingPath = '${tempDir.path}/missing.png';
    final emptyFile = await File('${tempDir.path}/empty.png').create();
    final repository = _FakeBodyPhotoRepository([
      _photo(id: 'latest-missing', recordId: 'r1', path: missingPath),
      _photo(id: 'latest-empty', recordId: 'r1', path: emptyFile.path),
      _photo(id: 'previous-valid', recordId: 'r1', path: frontGuideFile.path),
    ]);
    final container = ProviderContainer(
      overrides: [bodyPhotoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final path = await container.read(
      previousPhotoGuidePathProvider(BodyDirection.front).future,
    );

    expect(path, frontGuideFile.path);
    expect(repository.requestedDirection, BodyDirection.front);
  });
}

PhotoRecord _record(String id, DateTime shotAt) {
  return PhotoRecord(
    id: id,
    shotAt: shotAt,
    createdAt: shotAt,
    updatedAt: shotAt,
  );
}

BodyPhoto _photo({
  required String id,
  required String recordId,
  required String path,
  BodyDirection direction = BodyDirection.front,
}) {
  return BodyPhoto(
    id: id,
    recordId: recordId,
    filePath: path,
    direction: direction,
    createdAt: DateTime(2026, 1, 1),
  );
}

class _FakeBodyPhotoRepository implements BodyPhotoRepository {
  final List<BodyPhoto> photos;
  BodyDirection? requestedDirection;

  _FakeBodyPhotoRepository(this.photos);

  @override
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction) async {
    requestedDirection = direction;
    return photos;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<BodyPhoto?> getById(String id) async => null;

  @override
  Future<void> insert(BodyPhoto photo) async {}

  @override
  Future<List<BodyPhoto>> listAll() async => photos;

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async => photos;

  @override
  Future<void> update(BodyPhoto photo) async {}
}
