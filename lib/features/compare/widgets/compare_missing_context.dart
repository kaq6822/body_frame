import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';

/// 필요한 쿼리 파라미터/전달 데이터 없이 화면에 진입한 경우(예: 딥링크,
/// 뒤로가기 후 재진입)를 위한 안내 화면. 임의로 성공을 가정하지 않고
/// 사용자를 이전 단계로 되돌린다.
class CompareMissingContext extends StatelessWidget {
  final String memberId;
  final String message;
  final String backButtonId;

  const CompareMissingContext({
    super.key,
    required this.memberId,
    this.message = '비교 날짜 선택 화면에서 다시 진입해 주세요.',
    this.backButtonId = 'compare.missingContext.backToDates.button',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Semantics(
              identifier: backButtonId,
              label: '비교 날짜 선택으로 이동',
              child: ElevatedButton(
                key: ValueKey(backButtonId),
                onPressed: () => context.goNamed(
                  AppRoutes.compareDates,
                  pathParameters: {AppParams.memberId: memberId},
                ),
                child: const Text('비교 날짜 선택으로 이동'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
