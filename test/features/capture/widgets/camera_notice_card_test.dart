import 'package:body_frame/core/theme/app_theme.dart';
import 'package:body_frame/features/capture/widgets/camera_notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 미리보기 자리 안내 카드 검증.
///
/// 이 카드는 카메라를 열 수 없을 때 앱의 첫 화면 전체를 대신한다. 그래서
/// "무엇을 하면 되는지"가 어떤 폭에서도 읽혀야 하고, 상태 식별자와 재시도 버튼
/// 키는 화면 테스트·스크린리더가 의존하는 계약이다.
void main() {
  Widget host(Widget child, {Size size = const Size(360, 720)}) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  testWidgets('상태 식별자와 재시도 버튼 키는 statusId에서 파생한다', (tester) async {
    await tester.pumpWidget(
      host(
        CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.failure,
          title: '카메라를 사용할 수 없습니다.',
          onRetry: () {},
        ),
      ),
    );

    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier('screen.capture.camera.status'),
          )
          .value,
      'failure',
    );
    expect(
      find.byKey(const ValueKey('screen.capture.camera.status.retry.button')),
      findsOneWidget,
    );
  });

  testWidgets('진행 중에는 스피너만 두고 실패 아이콘·재시도를 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      host(
        const CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.busy,
          title: '카메라를 준비하는 중입니다.',
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(
      tester
          .getSemantics(
            find.bySemanticsIdentifier('screen.capture.camera.status'),
          )
          .value,
      'busy',
    );
  });

  testWidgets('좁은 폭에서도 설정 경로가 넘치지 않는다', (tester) async {
    // 위젯을 나열해 조립하면 폭이 모자랄 때 RenderFlex가 오버플로했다.
    await tester.pumpWidget(
      host(
        const CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.actionNeeded,
          title: '카메라 권한이 필요합니다.',
          settingsPath: ['설정', '애플리케이션', 'Body Frame', '권한', '카메라'],
        ),
        size: const Size(200, 720),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('경로를 읽어 줄 때는 화살표 대신 순서대로 들려준다', (tester) async {
    // 테스트 본문이 끝나는 시점에 검증되므로 addTearDown으로는 늦다.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        const CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.actionNeeded,
          title: '카메라 권한이 필요합니다.',
          settingsPath: ['설정', '권한', '카메라'],
        ),
      ),
    );

    expect(find.bySemanticsLabel('설정, 권한, 카메라'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('제목과 설명은 보이는 글자만 묶고 읽어 줄 문장은 원문으로 둔다', (tester) async {
    // 테스트 본문이 끝나는 시점에 검증되므로 addTearDown으로는 늦다.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        const CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.actionNeeded,
          title: '카메라 권한이 필요합니다.',
          description: '촬영을 시작하려면 기기 설정에서 카메라 접근을 허용해주세요.',
        ),
      ),
    );

    // 스크린리더가 듣는 문장에는 보이지 않는 문자가 섞이지 않아야 한다.
    expect(find.bySemanticsLabel('카메라 권한이 필요합니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('촬영을 시작하려면 기기 설정에서 카메라 접근을 허용해주세요.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('보조 동선은 재시도 아래에 함께 놓인다', (tester) async {
    await tester.pumpWidget(
      host(
        CameraNoticeCard(
          statusId: 'screen.capture.camera.status',
          tone: CameraNoticeTone.actionNeeded,
          title: '카메라 권한이 필요합니다.',
          onRetry: () {},
          secondaryAction: TextButton(
            key: const ValueKey('notice.secondary'),
            onPressed: () {},
            child: const Text('기록 보기'),
          ),
        ),
      ),
    );

    final retryY = tester
        .getCenter(
          find.byKey(
            const ValueKey('screen.capture.camera.status.retry.button'),
          ),
        )
        .dy;
    final secondaryY = tester
        .getCenter(find.byKey(const ValueKey('notice.secondary')))
        .dy;

    expect(secondaryY, greaterThan(retryY));
  });
}
