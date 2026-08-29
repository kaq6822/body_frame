import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/capture/capture_review_screen.dart';
import '../../features/capture/gallery_import_screen.dart';
import '../../features/capture/grid_camera_screen.dart';
import '../../features/compare/compare_dates_screen.dart';
import '../../features/compare/compare_direction_screen.dart';
import '../../features/compare/compare_export_screen.dart';
import '../../features/compare/compare_view_screen.dart';
import '../../features/records/photo_view_screen.dart';
import '../../features/records/record_detail_screen.dart';
import '../../features/records/records_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/storage_screen.dart';
import 'app_routes.dart';

/// 앱 라우터.
///
/// 루트가 촬영 화면이다. 앱을 열면 카메라가 바로 뜨고, 기록·설정·비교는 모두
/// 그 위로 쌓이는 화면이라 뒤로가기가 항상 카메라로 돌아온다.
///
/// 경로 파라미터는 [AppParams] 키를 사용한다. 화면 이동은
/// `context.goNamed(...)` / `context.pushNamed(...)`에 [AppRoutes] 이름을 쓴다.
GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      // 1. 홈 = 연속 세션 촬영 (+ 하위 라우트)
      GoRoute(
        path: '/',
        name: AppRoutes.home,
        builder: (context, state) => const GridCameraScreen(),
        routes: [
          // 2. 촬영 결과 일괄 확인
          GoRoute(
            path: 'review',
            name: AppRoutes.captureReview,
            builder: (context, state) => const CaptureReviewScreen(),
          ),
          // 3. 갤러리 사진 등록
          GoRoute(
            path: 'import',
            name: AppRoutes.galleryImport,
            builder: (context, state) => const GalleryImportScreen(),
          ),
          // 4. 촬영 기록 타임라인 (+ 하위 라우트)
          GoRoute(
            path: 'records',
            name: AppRoutes.records,
            builder: (context, state) => const RecordsScreen(),
            routes: [
              // 5. 촬영 기록 상세
              GoRoute(
                path: ':${AppParams.recordId}',
                name: AppRoutes.recordDetail,
                builder: (context, state) => RecordDetailScreen(
                  recordId: state.pathParameters[AppParams.recordId]!,
                ),
                routes: [
                  // 6. 원본 사진 보기
                  GoRoute(
                    path: 'photos/:${AppParams.photoId}',
                    name: AppRoutes.photoView,
                    builder: (context, state) => PhotoViewScreen(
                      recordId: state.pathParameters[AppParams.recordId]!,
                      photoId: state.pathParameters[AppParams.photoId]!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 7. 비교 날짜 선택
          GoRoute(
            path: 'compare',
            name: AppRoutes.compareDates,
            builder: (context, state) => const CompareDatesScreen(),
            routes: [
              // 8. 비교 방향 선택
              GoRoute(
                path: 'direction',
                name: AppRoutes.compareDirection,
                builder: (context, state) => const CompareDirectionScreen(),
              ),
              // 9. 전후 사진 비교
              GoRoute(
                path: 'view',
                name: AppRoutes.compareView,
                builder: (context, state) => const CompareViewScreen(),
              ),
              // 10. 비교 이미지 저장 설정
              GoRoute(
                path: 'export',
                name: AppRoutes.compareExport,
                builder: (context, state) => const CompareExportScreen(),
              ),
            ],
          ),
        ],
      ),

      // 11. 전체 설정 (+ 하위 설정 라우트)
      GoRoute(
        path: '/settings',
        name: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          // 12. 저장 공간 관리
          GoRoute(
            path: 'storage',
            name: AppRoutes.storage,
            builder: (context, state) => const StorageScreen(),
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
}
