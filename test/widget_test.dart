import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/features/home/home_screen.dart';
import 'package:body_frame/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 홈 타임라인은 실제 sqflite 기반 리포지토리를 조회한다. 이 앱 부팅
  // 테스트는 DB/네이티브 플러그인 없이 UI 흐름만 검증하는 것이 목적이므로
  // 리포지토리를 인메모리 Fake로 override한다. override하지 않으면 실제
  // 플러그인 채널 호출이 끝나지 않아 화면이 계속 로딩 상태로 남고, 그 반복
  // 애니메이션 때문에 pumpAndSettle()이 타임아웃된다.
  Widget buildApp(AppImagePicker picker) {
    return ProviderScope(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(
          _EmptyPhotoRecordRepository(),
        ),
        bodyPhotoRepositoryProvider.overrideWithValue(
          _EmptyBodyPhotoRepository(),
        ),
        appImagePickerProvider.overrideWithValue(picker),
        imagePickerRequestStoreProvider.overrideWithValue(
          _EmptyImagePickerRequestStore(),
        ),
      ],
      child: const BodyFrameApp(),
    );
  }

  testWidgets('앱이 홈 타임라인으로 바로 시작한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final picker = _CountingLostDataPicker();

    await tester.pumpWidget(buildApp(picker));
    await tester.pumpAndSettle();

    // 안정적인 화면 식별자 확인(Semantics identifier + ValueKey).
    expect(find.byKey(const ValueKey(HomeScreen.screenId)), findsOneWidget);
    expect(find.text('아직 기록이 없습니다'), findsOneWidget);
    expect(picker.retrieveLostDataCalls, 1);
  });

  testWidgets('홈에서 설정 화면으로 진입한다', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildApp(_CountingLostDataPicker()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home.settings.button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('screen.settings.home')), findsOneWidget);
    // 잠금/백업/개인정보 항목은 더 이상 존재하지 않는다.
    expect(find.byKey(const ValueKey('settings.grid.item')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.storage.item')), findsOneWidget);
  });
}

class _EmptyPhotoRecordRepository implements PhotoRecordRepository {
  @override
  Future<void> delete(String id) async {}

  @override
  Future<PhotoRecord?> getById(String id) async => null;

  @override
  Future<void> insert(PhotoRecord record) async {}

  @override
  Future<List<PhotoRecord>> listAll() async => const [];

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
