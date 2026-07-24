import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_body_photo_repository.dart';
import 'fakes/fake_member_repository.dart';
import 'fakes/fake_photo_record_repository.dart';

/// 회원 관리 핵심 흐름: 등록 → 목록 표시 → 검색 → 삭제.
/// 리포지토리는 인메모리 Fake로 대체해 실제 DB/파일 I/O 없이 검증한다
/// (ARCHITECTURE.md §8).
void main() {
  testWidgets('회원 등록 → 목록 표시 → 검색 → 삭제', (tester) async {
    final fakeMembers = FakeMemberRepository();
    final fakeRecords = FakePhotoRecordRepository();
    // 회원 상세 화면이 memberRecordsWithPhotosProvider를 통해
    // bodyPhotoRepository.listByMember를 항상 호출하므로 함께 대체한다.
    final fakePhotos = FakeBodyPhotoRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberRepositoryProvider.overrideWithValue(fakeMembers),
          photoRecordRepositoryProvider.overrideWithValue(fakeRecords),
          bodyPhotoRepositoryProvider.overrideWithValue(fakePhotos),
        ],
        child: MaterialApp.router(
          routerConfig: createAppRouter(initialLocation: '/members'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 초기 상태: 빈 목록.
    expect(find.byKey(const ValueKey('screen.members.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('members.list.empty')), findsOneWidget);

    // 첫 번째 회원 등록.
    await tester.tap(find.byKey(const ValueKey('members.add.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.members.add')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('member.name.field')),
      '홍길동',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('members.save.button')));
    await tester.tap(find.byKey(const ValueKey('members.save.button')));
    await tester.pumpAndSettle();

    // 목록 표시 확인.
    expect(find.byKey(const ValueKey('screen.members.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('members.item.0')), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);

    // 두 번째 회원 등록.
    await tester.tap(find.byKey(const ValueKey('members.add.button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('member.name.field')),
      '김철수',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('members.save.button')));
    await tester.tap(find.byKey(const ValueKey('members.save.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('members.item.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('members.item.1')), findsOneWidget);

    // 검색: '홍'으로 필터링하면 홍길동만 남는다.
    await tester.enterText(
      find.byKey(const ValueKey('members.search.field')),
      '홍',
    );
    await tester.pumpAndSettle();

    expect(find.text('홍길동'), findsOneWidget);
    expect(find.text('김철수'), findsNothing);

    // 검색 해제 후 회원 상세로 진입해 삭제.
    await tester.enterText(
      find.byKey(const ValueKey('members.search.field')),
      '',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('홍길동'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.members.detail')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('members.detail.delete.button')),
    );
    await tester.tap(find.byKey(const ValueKey('members.detail.delete.button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('members.delete.confirm.button')));
    await tester.pumpAndSettle();

    // 삭제 후 목록으로 복귀, 홍길동은 사라지고 김철수만 남는다.
    expect(find.byKey(const ValueKey('screen.members.list')), findsOneWidget);
    expect(find.text('홍길동'), findsNothing);
    expect(find.text('김철수'), findsOneWidget);
  });
}
