import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_repository.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/repositories/body_photo_repository.dart';
import 'package:bodymark/core/repositories/photo_record_repository.dart';
import 'package:bodymark/core/services/app_image_picker.dart';
import 'package:bodymark/features/capture/providers/capture_providers.dart';
import 'package:bodymark/features/settings/settings_screen.dart';
import 'package:bodymark/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/capture/fake_capture_camera.dart';

/// 앱 부팅 흐름 테스트.
///
/// 홈은 촬영 화면이므로 실기기 카메라 대신 [FakeCaptureCameraController]를
/// 주입한다. 기록·설정도 이 화면에서만 진입하므로 두 동선까지 함께 확인한다.
void main() {
  // 기록 화면과 촬영 화면의 기록 썸네일은 실제 sqflite 기반 리포지토리를
  // 조회한다. 이 앱 부팅 테스트는 DB/네이티브 플러그인 없이 UI 흐름만 검증하는
  // 것이 목적이므로 리포지토리를 인메모리 Fake로 override한다. override하지
  // 않으면 실제 플러그인 채널 호출이 끝나지 않아 화면이 계속 로딩 상태로 남고,
  // 그 반복 애니메이션 때문에 pumpAndSettle()이 타임아웃된다.
  Widget buildApp(
    AppImagePicker picker, {
    FakeCaptureCameraController? camera,
  }) {
    final controller = camera ?? FakeCaptureCameraController();
    final records = _EmptyPhotoRecordRepository();
    final members = _MemoryMembers(records);
    return ProviderScope(
      overrides: [
        memberRepositoryProvider.overrideWithValue(members),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 4, 15)),
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(
          _EmptyBodyPhotoRepository(),
        ),
        appImagePickerProvider.overrideWithValue(picker),
        imagePickerRequestStoreProvider.overrideWithValue(
          _EmptyImagePickerRequestStore(),
        ),
        captureCameraControllerFactoryProvider.overrideWithValue(
          () => controller,
        ),
        previousPhotoGuidePathProvider.overrideWith((ref, direction) => null),
      ],
      child: const BodyMarkApp(),
    );
  }

  testWidgets('앱은 회원 화면으로 시작하고 카메라 권한을 요청하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final picker = _CountingLostDataPicker();
    final camera = FakeCaptureCameraController();
    await tester.pumpWidget(buildApp(picker, camera: camera));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.members.list')), findsOneWidget);
    expect(camera.initializeCalls, 0);
    expect(picker.retrieveLostDataCalls, 1);
  });
  testWidgets('회원·기록·설정 하단 탐색이 동작한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp(_CountingLostDataPicker()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('screen.lessons.records')),
      findsOneWidget,
    );
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(SettingsScreen.screenId)), findsOneWidget);
  });
  testWidgets('회원 등록은 전체 화면에서 이름과 목표를 저장한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp(_CountingLostDataPicker()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('members.add.button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('members.edit.0.field')),
        matching: find.byType(TextField),
      ),
      '김서연',
    );
    await tester.tap(find.byKey(const ValueKey('members.save.button')));
    await tester.pumpAndSettle();
    expect(find.text('김서연'), findsOneWidget);
  });

  testWidgets('회원 등록 후 사진 없이 레슨 일지를 저장·열람한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp(_CountingLostDataPicker()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('members.add.button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('members.edit.0.field')),
        matching: find.byType(TextField),
      ),
      '김서연',
    );
    await tester.tap(find.byKey(const ValueKey('members.save.button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('김서연'));
    await tester.pumpAndSettle();
    final addLesson = find.byKey(const ValueKey('members.lesson.add.button'));
    await tester.ensureVisible(addLesson);
    await tester.tap(addLesson);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.lessons.edit')), findsOneWidget);
    expect(find.textContaining('2026.11.04 (수) 오후 3:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lessons.save.button')));
    await tester.pumpAndSettle();
    expect(find.text('일지 또는 사진을 추가해주세요.'), findsOneWidget);
    final memo = find.descendant(
      of: find.byKey(const ValueKey('lessons.memo.field')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(memo);
    await tester.enterText(memo, '손목 부하를 줄이고 호흡을 확인함');
    await tester.tap(find.byKey(const ValueKey('lessons.save.button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.members.detail')), findsOneWidget);
    final card = find.text('손목 부하를 줄이고 호흡을 확인함');
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('screen.lessons.detail')), findsOneWidget);
    expect(find.text('사진 없이 작성한 레슨 기록이에요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _EmptyPhotoRecordRepository implements PhotoRecordRepository {
  final records = <String, PhotoRecord>{};
  @override
  Future<void> delete(String id) async {}

  @override
  Future<PhotoRecord?> getById(String id) async => records[id];

  @override
  Future<void> insert(PhotoRecord record) async {}

  @override
  Future<List<PhotoRecord>> listAll() async => records.values.toList();

  @override
  Future<void> update(PhotoRecord record) async {}
}

class _EmptyBodyPhotoRepository implements BodyPhotoRepository {
  @override
  Future<void> delete(String id) async {}

  @override
  Future<BodyPhoto?> getById(String id) async => null;

  @override
  Future<void> insert(BodyPhoto photo) async {}

  @override
  Future<List<BodyPhoto>> listAll() async => const [];

  @override
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction) async =>
      const [];

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async => const [];

  @override
  Future<void> update(BodyPhoto photo) async {}
}

class _CountingLostDataPicker implements AppImagePicker {
  int retrieveLostDataCalls = 0;

  @override
  bool get supportsLostDataRecovery => true;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;

  @override
  Future<List<XFile>> pickMultiImage() async => const [];

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCalls += 1;
    return LostDataResponse.empty();
  }
}

class _EmptyImagePickerRequestStore implements ImagePickerRequestStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {}

  @override
  Future<ImagePickerRequestContext?> load() async => null;

  @override
  Future<void> save(ImagePickerRequestContext context) async {}
}

class _MemoryMembers implements MemberRepository {
  final _EmptyPhotoRecordRepository records;
  _MemoryMembers(this.records);
  final members = <String, Member>{};
  @override
  Future<List<Member>> list() async => members.values.toList();
  @override
  Future<void> save(Member member) async {
    members[member.id] = member;
  }

  @override
  Future<void> delete(String id) async {
    members.remove(id);
  }

  @override
  Future<void> saveLesson(
    PhotoRecord record,
    List<BodyPhoto> addedPhotos,
  ) async {
    records.records[record.id] = record;
  }

  @override
  Future<void> linkRecord(
    String recordId,
    String memberId,
    DateTime lessonAt,
  ) async {}
}
