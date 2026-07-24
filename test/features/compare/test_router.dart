import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/features/compare/compare_dates_screen.dart';
import 'package:body_frame/features/compare/compare_direction_screen.dart';
import 'package:body_frame/features/compare/compare_export_screen.dart';
import 'package:body_frame/features/compare/compare_view_screen.dart';
import 'package:go_router/go_router.dart';

/// compare 화면 테스트 전용 라우터.
///
/// `core/router/app_router.dart`는 20개 화면을 모두 import하므로, 다른
/// 워커의 feature(settings 등)에 컴파일 에러가 있으면 그 전체를 통해
/// 이 feature 테스트까지 함께 깨진다. ARCHITECTURE.md §5 표의 compare
/// 하위 경로/이름/파라미터를 그대로 재현해 compare 화면만 독립적으로
/// 검증할 수 있게 한다(실제 app_router.dart의 compare 라우트와 동일한 구조).
GoRouter createCompareTestRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/members/:${AppParams.memberId}/compare',
        name: AppRoutes.compareDates,
        builder: (context, state) => CompareDatesScreen(
          memberId: state.pathParameters[AppParams.memberId]!,
        ),
        routes: [
          GoRoute(
            path: 'direction',
            name: AppRoutes.compareDirection,
            builder: (context, state) => CompareDirectionScreen(
              memberId: state.pathParameters[AppParams.memberId]!,
            ),
          ),
          GoRoute(
            path: 'view',
            name: AppRoutes.compareView,
            builder: (context, state) => CompareViewScreen(
              memberId: state.pathParameters[AppParams.memberId]!,
            ),
          ),
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
  );
}
