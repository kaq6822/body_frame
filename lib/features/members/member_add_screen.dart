import 'package:flutter/material.dart';

import 'widgets/member_form.dart';

/// 3. 회원 등록 화면. MVP.md 3.1.
///
/// 이름만 필수, 나머지(대표 사진/성별/생년·연령대/연락처/메모)는 선택 입력이다.
/// 등록일은 자동으로 현재 시각을 사용한다. 폼 자체는 [MemberFormBody]가 등록/
/// 수정 화면에서 공유한다.
class MemberAddScreen extends StatelessWidget {
  static const screenId = 'screen.members.add';

  const MemberAddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: screenId,
      container: true,
      label: '회원 등록',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('회원 등록')),
        body: const MemberFormBody(),
      ),
    );
  }
}
