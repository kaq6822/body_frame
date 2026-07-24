import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/capture/capture_direction_screen.dart';
import '../../features/capture/capture_review_screen.dart';
import '../../features/capture/gallery_import_screen.dart';
import '../../features/capture/grid_camera_screen.dart';
import '../../features/compare/compare_dates_screen.dart';
import '../../features/compare/compare_direction_screen.dart';
import '../../features/compare/compare_export_screen.dart';
import '../../features/compare/compare_view_screen.dart';
import '../../features/members/app_start_screen.dart';
import '../../features/members/member_add_screen.dart';
import '../../features/members/member_detail_screen.dart';
import '../../features/members/member_edit_screen.dart';
import '../../features/members/members_list_screen.dart';
import '../../features/records/photo_view_screen.dart';
import '../../features/records/record_detail_screen.dart';
import '../../features/settings/app_lock_screen.dart';
import '../../features/settings/backup_restore_screen.dart';
import '../../features/settings/privacy_info_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/storage_screen.dart';
import 'app_routes.dart';

/// 앱 라우터.
///
/// 경로 파라미터는 [AppParams] 키를 사용한다. 화면 진입 시
/// `context.goNamed(...)` / `context.pushNamed(...)`에 [AppRoutes] 이름을 쓴다.
GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      // 1. 앱 시작 화면
      GoRoute(
        path: '/',
        name: AppRoutes.appStart,
        builder: (context, state) => const AppStartScreen(),
      ),

      // 2. 회원 목록 화면 (+ 하위 회원 관련 라우트)
      GoRoute(
        path: '/members',
        name: AppRoutes.membersList,
        builder: (context, state) => const MembersListScreen(),
        routes: [
          // 3. 회원 등록 화면
          GoRoute(
            path: 'new',
            name: AppRoutes.memberAdd,
            builder: (context, state) => const MemberAddScreen(),
          ),
          // 4. 회원 상세 화면
          GoRoute(
            path: ':${AppParams.memberId}',
            name: AppRoutes.memberDetail,
            builder: (context, state) => MemberDetailScreen(
              memberId: state.pathParameters[AppParams.memberId]!,
            ),
            routes: [
              // 5. 회원 정보 수정 화면
              GoRoute(
                path: 'edit',
                name: AppRoutes.memberEdit,
                builder: (context, state) => MemberEditScreen(
                  memberId: state.pathParameters[AppParams.memberId]!,
                ),
              ),
              // 6. 촬영 방향 선택 화면
              GoRoute(
                path: 'capture',
                name: AppRoutes.captureDirection,
                builder: (context, state) => CaptureDirectionScreen(
                  memberId: state.pathParameters[AppParams.memberId]!,
                ),
                routes: [
                  // 7. 격자 카메라 화면
                  GoRoute(
                    path: 'camera',
                    name: AppRoutes.captureCamera,
                    builder: (context, state) => GridCameraScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                    ),
                  ),
                  // 8. 촬영 결과 확인 화면
                  GoRoute(
                    path: 'review',
                    name: AppRoutes.captureReview,
                    builder: (context, state) => CaptureReviewScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                    ),
                  ),
                ],
              ),
              // 9. 갤러리 사진 등록 화면
              GoRoute(
                path: 'import',
                name: AppRoutes.galleryImport,
                builder: (context, state) => GalleryImportScreen(
                  memberId: state.pathParameters[AppParams.memberId]!,
                ),
              ),
              // 10. 촬영 기록 상세 화면
              GoRoute(
                path: 'records/:${AppParams.recordId}',
                name: AppRoutes.recordDetail,
                builder: (context, state) => RecordDetailScreen(
                  memberId: state.pathParameters[AppParams.memberId]!,
                  recordId: state.pathParameters[AppParams.recordId]!,
                ),
                routes: [
                  // 11. 원본 사진 보기 화면
                  GoRoute(
                    path: 'photos/:${AppParams.photoId}',
                    name: AppRoutes.photoView,
                    builder: (context, state) => PhotoViewScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                      recordId: state.pathParameters[AppParams.recordId]!,
                      photoId: state.pathParameters[AppParams.photoId]!,
                    ),
                  ),
                ],
              ),
              // 12. 비교 날짜 선택 화면
              GoRoute(
                path: 'compare',
                name: AppRoutes.compareDates,
                builder: (context, state) => CompareDatesScreen(
                  memberId: state.pathParameters[AppParams.memberId]!,
                ),
                routes: [
                  // 13. 비교 방향 선택 화면
                  GoRoute(
                    path: 'direction',
                    name: AppRoutes.compareDirection,
                    builder: (context, state) => CompareDirectionScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                    ),
                  ),
                  // 14. 전후 사진 비교 화면
                  GoRoute(
                    path: 'view',
                    name: AppRoutes.compareView,
                    builder: (context, state) => CompareViewScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                    ),
                  ),
                  // 15. 비교 이미지 저장 설정 화면
                  GoRoute(
                    path: 'export',
                    name: AppRoutes.compareExport,
                    builder: (context, state) => CompareExportScreen(
                      memberId: state.pathParameters[AppParams.memberId]!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // 16. 앱 설정 화면 (+ 하위 설정 라우트)
      GoRoute(
        path: '/settings',
        name: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          // 17. 앱 잠금 설정 화면
          GoRoute(
            path: 'lock',
            name: AppRoutes.appLock,
            builder: (context, state) => const AppLockScreen(),
          ),
          // 18. 백업 및 복원 화면
          GoRoute(
            path: 'backup',
            name: AppRoutes.backupRestore,
            builder: (context, state) => const BackupRestoreScreen(),
          ),
          // 19. 저장 공간 관리 화면
          GoRoute(
            path: 'storage',
            name: AppRoutes.storage,
            builder: (context, state) => const StorageScreen(),
          ),
          // 20. 개인정보 및 이용 안내 화면
          GoRoute(
            path: 'privacy',
            name: AppRoutes.privacyInfo,
            builder: (context, state) => const PrivacyInfoScreen(),
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
