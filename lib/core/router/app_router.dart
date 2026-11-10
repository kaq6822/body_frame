import '../../features/capture/capture_guide_screen.dart';
import '../../features/settings/information_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import 'app_routes.dart';

/// Members are the entry point. Camera exists only inside an explicit capture flow.
GoRouter createAppRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/capture-guide',
      builder: (_, _) => const CaptureGuideScreen(),
    ),
    GoRoute(
      path: '/',
      name: AppRoutes.home,
      builder: (_, _) => const MembersScreen(),
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
    GoRoute(
      path: '/records',
      name: AppRoutes.records,
      // 설정의 "기존 기록 연결"은 `?member=unlinked`로 회원 미연결 기록만 연다.
      builder: (_, s) => LessonRecordsScreen(
        initialMemberFilter: s.uri.queryParameters[AppParams.memberFilter],
      ),
      routes: [
        GoRoute(
          path: ':${AppParams.recordId}',
          name: AppRoutes.recordDetail,
          builder: (_, s) => LessonDetailScreen(
            recordId: s.pathParameters[AppParams.recordId]!,
          ),
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
    GoRoute(
      path: '/settings',
      name: AppRoutes.settings,
      builder: (_, _) => const SettingsScreen(),
      routes: [
        GoRoute(path: 'data', builder: (_, _) => const InformationScreen()),
        GoRoute(
          path: 'privacy',
          builder: (_, _) => const InformationScreen(privacy: true),
        ),
        GoRoute(
          path: 'storage',
          name: AppRoutes.storage,
          builder: (_, _) => const StorageScreen(),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    key: const ValueKey('screen.error'),
    appBar: AppBar(title: const Text('오류')),
    body: Center(child: Text('경로를 찾을 수 없습니다: ${state.uri}')),
  ),
);
