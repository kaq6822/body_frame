import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:body_frame/core/router/app_routes.dart';
import 'providers/capture_providers.dart';
import 'providers/capture_session_provider.dart';
import 'widgets/async_status_indicator.dart';
import 'widgets/capture_member_banner.dart';
import 'widgets/direction_selector.dart';

/// 6. 촬영 방향 선택 화면. MVP.md 4.2.
///
/// 정면/좌측면/우측면/후면/기타 중 하나를 선택하면 격자 카메라 화면으로
/// 이동한다. MVP.md 4.1: 잘못된 회원 등록을 막기 위해 대상 회원 이름을
/// 화면에 명확히 표시한다.
class CaptureDirectionScreen extends ConsumerWidget {
  static const screenId = 'screen.capture.direction';

  final String memberId;

  const CaptureDirectionScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));

    return Semantics(
      identifier: screenId,
      container: true,
      label: '촬영 방향 선택',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('촬영 방향 선택')),
        body: memberAsync.when(
          data: (member) {
            if (member == null) {
              return const Center(
                key: ValueKey('capture.direction.memberNotFound'),
                child: Text('회원 정보를 찾을 수 없습니다.'),
              );
            }
            return _DirectionBody(memberId: memberId, memberName: member.name);
          },
          loading: () => const Center(
            child: AsyncStatusIndicator(
              statusId: 'screen.capture.direction.status',
              status: AsyncStatus.busy,
              busyLabel: '회원 정보를 불러오는 중입니다.',
            ),
          ),
          error: (error, stackTrace) => Center(
            child: AsyncStatusIndicator(
              statusId: 'screen.capture.direction.status',
              status: AsyncStatus.failure,
              failureMessage: '회원 정보를 불러오지 못했습니다.',
              onRetry: () => ref.invalidate(memberByIdProvider(memberId)),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectionBody extends ConsumerWidget {
  final String memberId;
  final String memberName;

  const _DirectionBody({required this.memberId, required this.memberName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptureMemberBanner(memberName: memberName),
          const SizedBox(height: 12),
          const Text('촬영할 방향을 선택하세요. 한 번의 방문에 모든 방향을 촬영하지 않아도 됩니다.'),
          const SizedBox(height: 24),
          DirectionSelector(
            idPrefix: 'capture.direction',
            selected: null,
            onSelected: (direction) {
              ref
                  .read(captureSessionProvider(memberId).notifier)
                  .selectDirection(direction);
              context.pushNamed(
                AppRoutes.captureCamera,
                pathParameters: {AppParams.memberId: memberId},
              );
            },
          ),
        ],
      ),
    );
  }
}
