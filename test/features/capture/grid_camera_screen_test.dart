import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/features/capture/camera/capture_camera_controller.dart';
import 'package:body_frame/features/capture/grid_camera_screen.dart';
import 'package:body_frame/features/capture/providers/capture_providers.dart';
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

  setUp(() {
    // GridSettingsServiceImpl이 내부에서 사용하는 shared_preferences 목 초기화.
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 1, 1);
    member = Member(id: memberId, name: '홍길동', createdAt: now, updatedAt: now);
  });

  Widget buildApp(CaptureCameraController Function() factory) {
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
        memberRepositoryProvider.overrideWithValue(_FakeMemberRepository(member)),
        captureCameraControllerFactoryProvider.overrideWithValue(factory),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('카메라 초기화 성공 시 셔터를 누르면 결과 확인 화면으로 이동한다', (tester) async {
    final fake = _FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(() => fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(GridCameraScreen.screenId)), findsOneWidget);
    expect(find.byKey(const ValueKey('capture.shutter.button')), findsOneWidget);
    // 회원 이름이 상시 표시되는지 확인(MVP.md 4.1).
    expect(find.textContaining('홍길동'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('capture.shutter.button')));
    await tester.pumpAndSettle();

    expect(fake.takePictureCalls, 1);
    expect(find.byKey(const ValueKey('screen.capture.review.stub')), findsOneWidget);
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

class _FakeCaptureCameraController implements CaptureCameraController {
  final bool initializeShouldFail;
  final String capturedPath = '/tmp/fake_capture.jpg';
  bool _initialized = false;
  int takePictureCalls = 0;

  _FakeCaptureCameraController({this.initializeShouldFail = false});

  @override
  double get aspectRatio => 3 / 4;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
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
    _initialized = false;
  }
}
