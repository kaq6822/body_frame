import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
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

/// 격자 카메라 화면 위젯 테스트.
///
/// `camera` 패키지는 실기기 하드웨어에 의존하므로 [CaptureCameraController]를
/// 가짜로 교체해(ProviderScope override) 초기화 성공/실패, 셔터 촬영 →
/// 결과 확인 화면 이동을 실기기 없이 검증한다.
void main() {
  const memberId = 'm1';
  late Member member;
  late Directory tempDir;
  late File frontGuideFile;
  late File sideGuideFile;

  setUp(() async {
    // GridSettingsServiceImpl이 내부에서 사용하는 shared_preferences 목 초기화.
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 1, 1);
    member = Member(id: memberId, name: '홍길동', createdAt: now, updatedAt: now);
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
    Future<String?> Function(PreviousPhotoGuideKey key)? loadPreviousGuide,
  }) {
    final guideLoader = loadPreviousGuide ?? (_) async => null;
    final router = GoRouter(
      initialLocation: '/members/$memberId/capture/camera',
      routes: [
        GoRoute(
          path: '/members/:memberId/capture/camera',
          name: AppRoutes.captureCamera,
          builder: (context, state) => GridCameraScreen(
            memberId: state.pathParameters[AppParams.memberId]!,
          ),
        ),
        GoRoute(
          path: '/members/:memberId/capture/review',
          name: AppRoutes.captureReview,
          builder: (context, state) => Scaffold(
            key: const ValueKey('screen.capture.review.stub'),
            body: const Text('review stub'),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(
          _FakeMemberRepository(member),
        ),
        captureCameraControllerFactoryProvider.overrideWithValue(factory),
        previousPhotoGuidePathProvider.overrideWith(
          (ref, key) => guideLoader(key),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('카메라 초기화 성공 시 셔터를 누르면 결과 확인 화면으로 이동한다', (tester) async {
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(GridCameraScreen.screenId)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('capture.shutter.button')),
      findsOneWidget,
    );
    // 회원 이름이 상시 표시되는지 확인.
    expect(find.textContaining('홍길동'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 1);
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
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.status'),
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

    await tester.tap(
      find.byKey(const ValueKey('capture.previousGuide.toggle')),
    );
    await tester.pump();
    expect(
      find.bySemanticsIdentifier('capture.previousGuide.image'),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('capture.previousGuide.toggle')),
    );
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GridCameraScreen)),
    );
    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 1);
    expect(
      container.read(captureSessionProvider(memberId)).capturedImagePath,
      fake.capturedPath,
    );
  });

  testWidgets('촬영 방향이 바뀌면 같은 회원의 해당 방향 가이드로 교체한다', (tester) async {
    final requested = <PreviousPhotoGuideKey>[];
    await tester.pumpWidget(
      buildApp(
        _FakeCaptureCameraController.new,
        loadPreviousGuide: (key) async {
          requested.add(key);
          return key.direction == BodyDirection.front
              ? frontGuideFile.path
              : sideGuideFile.path;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requested.last.memberId, memberId);
    expect(requested.last.direction, BodyDirection.front);
    expect(
      find.byKey(
        ValueKey('capture.previousGuide.image.${frontGuideFile.path}'),
      ),
      findsOneWidget,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GridCameraScreen)),
    );
    container
        .read(captureSessionProvider(memberId).notifier)
        .selectDirection(BodyDirection.leftSide);
    await tester.pumpAndSettle();

    expect(requested.last.memberId, memberId);
    expect(requested.last.direction, BodyDirection.leftSide);
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
      previousPhotoGuidePathProvider((
        memberId: memberId,
        direction: BodyDirection.front,
      )).future,
    );

    expect(path, frontGuideFile.path);
    expect(repository.requestedMemberId, memberId);
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

class _FakeBodyPhotoRepository implements BodyPhotoRepository {
  final List<BodyPhoto> photos;
  String? requestedMemberId;
  BodyDirection? requestedDirection;

  _FakeBodyPhotoRepository(this.photos);

  @override
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async {
    requestedMemberId = memberId;
    requestedDirection = direction;
    return photos;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteByRecord(String recordId) async {}

  @override
  Future<BodyPhoto?> getById(String id) async => null;

  @override
  Future<void> insert(BodyPhoto photo) async {}

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async => photos;

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
