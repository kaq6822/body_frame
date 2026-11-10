import 'package:bodymark/core/app_info.dart';
import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/router/app_router.dart';
import 'package:bodymark/core/services/grid_settings_service.dart';
import 'package:bodymark/features/members/lesson_records_screen.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:bodymark/features/settings/providers/settings_providers.dart';
import 'package:bodymark/features/settings/services/app_settings_service.dart';
import 'package:bodymark/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 화면(Stitch 44)의 브랜드·버전 카드, 격자 기본값, 기존 기록 연결,
/// 저장 알림 자동 숨김을 확인한다. 저장소와 기록은 모두 Fake로 대체한다.
void main() {
  late _FakeAppSettingsService appSettings;
  late _FakeGridSettingsService grid;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appSettings = _FakeAppSettingsService();
    grid = _FakeGridSettingsService();
  });

  Future<void> pumpSettings(WidgetTester tester, {int unlinked = 0}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(appSettings),
          gridSettingsServiceProvider.overrideWithValue(grid),
          unlinkedRecordCountProvider.overrideWith((ref) async => unlinked),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String? subtitleOf(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('settings.linkRecords.subtitle')))
      .data;

  testWidgets('맨 위 브랜드 카드에 앱 이름과 pubspec 버전을 보여 준다', (tester) async {
    await pumpSettings(tester);
    final card = find.byKey(const ValueKey('settings.brand.card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text(AppInfo.name)),
      findsOneWidget,
    );
    expect(find.text('v${AppInfo.version}'), findsOneWidget);
    // 첫 섹션보다 위에 있다.
    expect(
      tester.getTopLeft(card).dy,
      lessThan(tester.getTopLeft(find.text('촬영')).dy),
    );
  });

  testWidgets('격자 표시 기본값 스위치는 촬영 격자 설정에 저장된다', (tester) async {
    grid.persisted = GridSettings.defaults.copyWith(spacing: 80);
    await pumpSettings(tester);
    final toggle = find.byKey(const ValueKey('settings.capture.grid.switch'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(grid.saved.last.visible, isFalse);
    // 다른 격자 값은 그대로 남는다.
    expect(grid.saved.last.spacing, 80);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('저장 성공 알림은 2초 뒤 사라지고 실패 알림은 남는다', (tester) async {
    await pumpSettings(tester);
    const statusKey = ValueKey('screen.settings.save.status');
    final feedback = find.byKey(
      const ValueKey('settings.capture.countdownFeedback.switch'),
    );

    await tester.tap(feedback);
    await tester.pump();
    await tester.pump();
    expect(find.text('설정을 저장했어요.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('설정을 저장했어요.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('설정을 저장했어요.'), findsNothing);
    expect(find.byKey(statusKey), findsNothing);

    appSettings.failSave = true;
    await tester.tap(feedback);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('설정을 저장하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screen.settings.save.status.retry.button')),
      findsOneWidget,
    );
  });

  testWidgets('다른 화면에서 끝난 저장 성공은 설정에 들어올 때 보이지 않는다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appSettingsServiceProvider.overrideWithValue(appSettings),
        gridSettingsServiceProvider.overrideWithValue(grid),
        unlinkedRecordCountProvider.overrideWith((ref) async => 0),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appSettingsControllerProvider.future);
    // 촬영 빠른 설정에서 바꾼 것처럼 화면 밖에서 저장을 끝낸다.
    await container
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(capture: s.capture.copyWith(showLevel: false)),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('설정을 저장했어요.'), findsNothing);
  });

  testWidgets('회원 미연결 기록이 없으면 "연결할 기록 없음"을 보여 준다', (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.linkRecords.item')),
      200,
    );
    expect(subtitleOf(tester), keepPhrasesWhole('연결할 기록 없음'));
  });

  testWidgets('기존 기록 연결은 기록 탭을 회원 미연결 필터로 연다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final at = DateTime(2026, 11, 4, 15);
    var countReads = 0;
    RecordWithPhotos item(String id, String? memberId, String memo) =>
        RecordWithPhotos(
          record: PhotoRecord(
            id: id,
            memberId: memberId,
            memo: memo,
            shotAt: at,
            createdAt: at,
            updatedAt: at,
          ),
          photos: const [],
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(appSettings),
          gridSettingsServiceProvider.overrideWithValue(grid),
          unlinkedRecordCountProvider.overrideWith((ref) async {
            countReads++;
            return 1;
          }),
          membersProvider.overrideWith(
            (ref) async => [
              Member(id: 'm1', name: '김서연', createdAt: at, updatedAt: at),
            ],
          ),
          timelineProvider.overrideWith(
            (ref) async => [
              item('linked', 'm1', '연결된 기록 메모'),
              item('orphan', null, '미연결 기록 메모'),
            ],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: createAppRouter(initialLocation: '/settings'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 탭 루트로 연 설정에는 탭이 보인다.
    expect(find.byKey(const ValueKey('main.navigation')), findsOneWidget);
    final link = find.byKey(const ValueKey('settings.linkRecords.item'));
    await tester.scrollUntilVisible(link, 200);
    expect(subtitleOf(tester), keepPhrasesWhole('회원 미연결 기록 1개'));
    await tester.tap(link);
    await tester.pumpAndSettle();

    final screen = tester.widget<LessonRecordsScreen>(
      find.byType(LessonRecordsScreen),
    );
    expect(screen.initialMemberFilter, 'unlinked');
    // push로 연 기록 화면에는 탭이 없다. 탭의 go가 아래 스택을 버리기 때문이다.
    expect(find.byKey(const ValueKey('main.navigation')), findsNothing);
    expect(find.textContaining('미연결 기록 메모'), findsOneWidget);
    expect(find.textContaining('연결된 기록 메모'), findsNothing);

    // push로 열었으므로 뒤로 가면 설정으로 돌아오고 개수를 다시 읽는다.
    final readsBefore = countReads;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(countReads, greaterThan(readsBefore));
  });
}

class _FakeAppSettingsService implements AppSettingsService {
  AppSettings? persisted;
  final List<AppSettings> saved = [];
  bool failSave = false;

  @override
  Future<AppSettings> load() async => persisted ?? AppSettings.defaults;

  @override
  Future<void> save(AppSettings settings) async {
    if (failSave) throw StateError('설정 저장 실패(테스트)');
    persisted = settings;
    saved.add(settings);
  }
}

class _FakeGridSettingsService implements GridSettingsService {
  GridSettings persisted = GridSettings.defaults;
  final List<GridSettings> saved = [];

  @override
  Future<GridSettings> load() async => persisted;

  @override
  Future<void> save(GridSettings settings) async {
    persisted = settings;
    saved.add(settings);
  }

  @override
  Future<void> reset() async {
    persisted = GridSettings.defaults;
  }
}
