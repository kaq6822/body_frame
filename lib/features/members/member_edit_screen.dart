import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import 'providers/members_providers.dart';
import 'widgets/async_status.dart';
import 'widgets/member_form.dart';

/// 5. 회원 정보 수정 화면. MVP.md 3.3.
///
/// 등록 화면과 동일한 [MemberFormBody]를 기존 회원 값으로 초기화해 재사용한다.
class MemberEditScreen extends ConsumerWidget {
  static const screenId = 'screen.members.edit';

  final String memberId;

  const MemberEditScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberDetailProvider(memberId));

    return Semantics(
      identifier: screenId,
      container: true,
      label: '회원 정보 수정',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('회원 정보 수정')),
        body: AsyncValueView<Member?>(
          value: memberAsync,
          statusId: '$screenId.status',
          onRetry: () => ref.invalidate(memberDetailProvider(memberId)),
          builder: (member) {
            if (member == null) {
              return const Center(child: Text('회원 정보를 찾을 수 없습니다.'));
            }
            return MemberFormBody(existing: member);
          },
        ),
      ),
    );
  }
}
