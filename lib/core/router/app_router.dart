import '../../features/capture/capture_guide_screen.dart';
import '../../features/settings/information_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_screen.dart';
import '../../features/members/member_screens.dart';
import '../../features/members/lesson_screens.dart';
import '../../features/capture/capture_review_screen.dart';
import '../../features/capture/gallery_import_screen.dart';
import '../../features/capture/grid_camera_screen.dart';
import '../../features/compare/compare_direction_screen.dart';
import '../../features/compare/compare_export_screen.dart';
import '../../features/compare/compare_view_screen.dart';
import '../../features/records/photo_view_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/storage_screen.dart';
import '../../features/videos/video_camera_screen.dart';
import '../../features/videos/video_player_screen.dart';
import 'app_routes.dart';
import 'main_shell.dart';

/// 하단 탭 4개(홈·회원·기록·설정)는 한 틀([MainShell]) 안의 가지로 두어 탭
/// 바가 고정되고 탭마다 상태(스크롤·필터)가 유지된다. 나머지 화면은 모두 루트
/// 내비게이터에 올라가 탭 바를 덮는다.
GoRouter createAppRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute(
      builder: (_, _, shell) => MainShell(shell: shell),
      navigatorContainerBuilder: (_, shell, children) => FadingBranchContainer(
        currentIndex: shell.currentIndex,
        children: children,
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              name: AppRoutes.home,
              builder: (_, _) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/members',
              name: AppRoutes.members,
              builder: (_, _) => const MembersScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/records',
              name: AppRoutes.records,
              builder: (_, _) => const LessonRecordsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              name: AppRoutes.settings,
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/capture-guide',
      builder: (_, _) => const CaptureGuideScreen(),
    ),
    GoRoute(
      path: '/members/new',
      builder: (_, _) => const MemberEditorScreen(),
    ),
    GoRoute(
      path: '/members/:memberId/edit',
      builder: (_, s) =>
          MemberEditorScreen(memberId: s.pathParameters['memberId']!),
    ),
    GoRoute(
      path: '/members/:memberId/lessons/new',
      builder: (_, s) =>
          LessonEditorScreen(memberId: s.pathParameters['memberId']!),
    ),
    GoRoute(
      path: '/members/:memberId/lessons/:recordId/edit',
      builder: (_, s) => LessonEditorScreen(
        memberId: s.pathParameters['memberId']!,
        recordId: s.pathParameters['recordId']!,
      ),
    ),
    GoRoute(
      path: '/members/:memberId/compare',
      builder: (_, s) =>
          MemberCompareScreen(memberId: s.pathParameters['memberId']!),
    ),
    GoRoute(
      path: '/members/:memberId',
      builder: (_, s) =>
          MemberDetailScreen(memberId: s.pathParameters['memberId']!),
    ),
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
    // 레슨 편집이 push하고 녹화본(RecordedVideo)을 결과로 받는다.
    GoRoute(
      path: '/video-camera',
      name: AppRoutes.videoCamera,
      builder: (_, _) => const VideoCameraScreen(),
    ),
    GoRoute(
      path: '/camera',
      name: 'capture.camera',
      builder: (_, _) => const GridCameraScreen(),
      routes: [
        GoRoute(
          path: 'review',
          name: AppRoutes.captureReview,
          builder: (_, _) => const CaptureReviewScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/import',
      name: AppRoutes.galleryImport,
      builder: (_, _) => const GalleryImportScreen(),
    ),
    // 기록 탭과 같은 화면을 다른 화면 위에 연다. "기존 기록 연결"은
    // `?member=unlinked`로 회원 미연결 기록만 연다.
    GoRoute(
      path: AppRoutes.recordsPagePath,
      name: AppRoutes.recordsPage,
      builder: (_, s) => LessonRecordsScreen(
        initialMemberFilter: s.uri.queryParameters[AppParams.memberFilter],
      ),
    ),
    // 탭 경로 아래에 두면 탭 틀까지 함께 만들어지므로 최상위에 따로 둔다.
    GoRoute(
      path: '/records/:${AppParams.recordId}',
      name: AppRoutes.recordDetail,
      builder: (_, s) =>
          LessonDetailScreen(recordId: s.pathParameters[AppParams.recordId]!),
      routes: [
        GoRoute(
          path: 'photos/:${AppParams.photoId}',
          name: AppRoutes.photoView,
          builder: (_, s) => PhotoViewScreen(
            recordId: s.pathParameters[AppParams.recordId]!,
            photoId: s.pathParameters[AppParams.photoId]!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/compare',
      name: AppRoutes.compareDates,
      builder: (_, _) => const MembersScreen(),
      routes: [
        GoRoute(
          path: 'direction',
          name: AppRoutes.compareDirection,
          builder: (_, _) => const CompareDirectionScreen(),
        ),
        GoRoute(
          path: 'view',
          name: AppRoutes.compareView,
          builder: (_, _) => const CompareViewScreen(),
        ),
        GoRoute(
          path: 'export',
          name: AppRoutes.compareExport,
          builder: (_, _) => const CompareExportScreen(),
        ),
      ],
    ),
    // 카메라 위에서 여는 설정. 탭으로 가면 촬영 흐름이 버려진다.
    GoRoute(
      path: '/app-settings',
      name: AppRoutes.settingsPage,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/data',
      builder: (_, _) => const InformationScreen(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (_, _) => const InformationScreen(privacy: true),
    ),
    GoRoute(
      path: '/settings/storage',
      name: AppRoutes.storage,
      builder: (_, _) => const StorageScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    key: const ValueKey('screen.error'),
    appBar: AppBar(title: const Text('오류')),
    body: Center(child: Text('경로를 찾을 수 없습니다: ${state.uri}')),
  ),
);
