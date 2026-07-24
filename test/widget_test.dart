import 'package:body_frame/core/providers.dart';
import 'package:body_frame/features/members/app_start_screen.dart';
import 'package:body_frame/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/members/fakes/fake_member_repository.dart';

void main() {
  testWidgets('앱이 시작 화면을 렌더링하고 회원 목록으로 이동한다', (tester) async {
    // AppLockGate가 앱 설정(shared_preferences)을 읽어 잠금 여부를 판단하고,
    // 설정을 알 수 없는 동안에는 fail-safe로 화면을 가린다. 테스트에서는
    // 설정 저장소를 모킹해 즉시 resolve되도록 한다(RULE.md 8/10).
    SharedPreferences.setMockInitialValues({});
    // 회원 목록 화면은 실제 sqflite 기반 memberRepositoryProvider를 조회한다.
    // 이 앱 부팅 테스트는 DB/네이티브 플러그인 없이 UI 흐름만 검증하는 것이
    // 목적이므로, 리포지토리를 인메모리 Fake로 override한다(ARCHITECTURE.md §8).
    // override하지 않으면 실제 플러그인 채널 호출이 끝나지 않아 회원 목록
    // 화면이 계속 로딩(CircularProgressIndicator) 상태로 남고, 그 반복
    // 애니메이션 때문에 pumpAndSettle()이 타임아웃된다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
        ],
        child: const BodyFrameApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 시작 화면 식별자 확인 (RULE.md: Semantics identifier + ValueKey).
    expect(find.byKey(const ValueKey(AppStartScreen.screenId)), findsOneWidget);

    // '시작하기' 버튼으로 회원 목록 진입.
    await tester.tap(find.byKey(const ValueKey('app.start.enter.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('screen.members.list')), findsOneWidget);
  });
}
