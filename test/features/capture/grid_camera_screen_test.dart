import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/features/capture/camera/capture_camera_controller.dart';
import 'package:body_frame/features/capture/grid_camera_screen.dart';
import 'package:body_frame/features/capture/providers/capture_providers.dart';
import 'package:body_frame/features/capture/providers/capture_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 연속 세션 촬영 화면 위젯 테스트.
///
/// `camera` 패키지는 실기기 하드웨어에 의존하므로 [CaptureCameraController]를
/// 가짜로 교체해(ProviderScope override) 초기화 성공/실패, 방향 자동 전환,
/// 마지막 컷 이후 리뷰 이동을 실기기 없이 검증한다.
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
    CaptureCameraController Function() factory, {
    Future<String?> Function(BodyDirection direction)? loadPreviousGuide,
  }) {
    final guideLoader = loadPreviousGuide ?? (_) async => null;
    final router = GoRouter(
      initialLocation: '/capture',
      routes: [
        GoRoute(
          path: '/capture',
          name: AppRoutes.captureSession,
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
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        captureCameraControllerFactoryProvider.overrideWithValue(factory),
        previousPhotoGuidePathProvider.overrideWith(
          (ref, direction) => guideLoader(direction),
        ),
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

  testWidgets('실기기 폭에서 진행 칩 4개가 넘치지 않고 모두 보인다', (tester) async {
    // 기본 테스트 뷰포트(800x600 논리 픽셀)는 실기기보다 넓어 상단바 오버플로를
    // 놓친다. 흔한 1080x2400 @2.75(≈393dp) 화면을 그대로 재현한다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(_FakeCaptureCameraController.new));
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

  testWidgets('셔터를 누르면 화면을 벗어나지 않고 다음 방향으로 넘어간다', (tester) async {
    final fake = _FakeCaptureCameraController();
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
    final fake = _FakeCaptureCameraController();
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
    final fake = _FakeCaptureCameraController();
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
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();
    expect(sessionOf(tester).current.direction, BodyDirection.leftSide);

    await tester.tap(
      find.byKey(const ValueKey('capture.progress.step.front')),
    );
    await tester.pumpAndSettle();

    expect(sessionOf(tester).current.direction, BodyDirection.front);
  });

  testWidgets('찍은 컷이 없으면 완료 버튼이 비활성이고 한 장이라도 있으면 활성이다', (tester) async {
    final fake = _FakeCaptureCameraController();
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

  testWidgets('카메라 초기화 실패 시 실패 상태와 재시도 버튼을 노출한다', (tester) async {
    final fake = _FakeCaptureCameraController(initializeShouldFail: true);
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('screen.capture.camera.status.retry.button')),
      findsOneWidget,
    );
  });

  testWidgets('최근 사진을 원본 비율의 반투명 가이드로 표시하고 설정을 바꾼다', (tester) async {
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(
      buildApp(() => fake, loadPreviousGuide: (_) async => frontGuideFile.path),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsOneWidget,
    );
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

    await tester.tap(find.byKey(const ValueKey('capture.previousGuide.toggle')));
    await tester.pump();
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('capture.previousGuide.toggle')));
    await tester.pump();
    final sliderFinder = find.byKey(
      const ValueKey('capture.previousGuide.opacity.slider'),
    );
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
        _FakeCaptureCameraController.new,
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
      find.byKey(ValueKey('capture.previousGuide.image.${frontGuideFile.path}')),
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
      find.byKey(ValueKey('capture.previousGuide.image.${frontGuideFile.path}')),
      findsNothing,
    );
  });

  testWidgets('사용할 이전 파일이 없어도 카메라 촬영은 계속 사용할 수 있다', (tester) async {
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

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
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(
      buildApp(
        () => fake,
        loadPreviousGuide: (_) async => throw StateError('이전 사진 조회 실패(테스트)'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('이전 사진을 불러오지 못했습니다.'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('fake.camera.preview')), findsOneWidget);
  });

  testWidgets('앱이 비활성화되면 카메라를 해제하고 복귀 시 다시 초기화한다', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final fake = _FakeCaptureCameraController();
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
      _photo(id: 'latest-missing', path: missingPath),
      _photo(id: 'latest-empty', path: emptyFile.path),
      _photo(id: 'previous-valid', path: frontGuideFile.path),
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

BodyPhoto _photo({required String id, required String path}) {
  return BodyPhoto(
    id: id,
    recordId: 'r-$id',
    filePath: path,
    direction: BodyDirection.front,
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

class _FakeCaptureCameraController implements CaptureCameraController {
  final bool initializeShouldFail;
  final String capturedPath = '/tmp/fake_capture.jpg';
  bool _initialized = false;
  int initializeCalls = 0;
  int disposeCalls = 0;
  int takePictureCalls = 0;

  _FakeCaptureCameraController({this.initializeShouldFail = false});

  @override
  double get aspectRatio => 3 / 4;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (initializeShouldFail) {
      throw StateError('카메라를 사용할 수 없습니다(테스트).');
    }
    _initialized = true;
  }

  @override
  Widget buildPreview() => const SizedBox(key: ValueKey('fake.camera.preview'));

  @override
  Future<String> takePicture() async {
    takePictureCalls += 1;
    return capturedPath;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _initialized = false;
  }
}
