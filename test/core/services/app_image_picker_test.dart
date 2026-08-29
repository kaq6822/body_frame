import 'dart:io';
import 'dart:typed_data';

import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picker 요청 문맥을 영속화하고 정확히 일치할 때만 지운다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesImagePickerRequestStore();
    final expected = ImagePickerRequestContext.photoReplacement(
      recordId: 'record-1',
      photoId: 'photo-1',
    );
    await store.save(expected);

    expect(await store.load(), expected);
    await store.clearIfMatches(
      ImagePickerRequestContext.photoReplacement(
        recordId: 'record-1',
        photoId: 'photo-2',
      ),
    );
    expect(await store.load(), expected);

    await store.clearIfMatches(expected);
    expect(await store.load(), isNull);
  });

  test('유실 결과는 정확한 문맥이 화면 반영을 확인할 때까지 유지한다', () async {
    final expected = ImagePickerRequestContext.photoReplacement(
      recordId: 'record-1',
      photoId: 'photo-1',
    );
    final store = MemoryImagePickerRequestStore(expected);
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse(
        files: [
          XFile.fromData(Uint8List.fromList([1, 2, 3]), path: '/lost.jpg'),
        ],
      ),
      store: store,
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);

    await Future.wait([coordinator.initialize(), coordinator.initialize()]);

    expect(picker.retrieveLostDataCalls, 1);
    expect(store.current, expected);
    expect(store.recovered?.context, expected);
    expect(
      coordinator.recoveredFor(
        ImagePickerRequestContext.photoReplacement(
          recordId: 'record-2',
          photoId: 'photo-1',
        ),
      ),
      isNull,
    );
    expect(coordinator.state?.context, expected);

    final recovered = coordinator.recoveredFor(expected);
    expect(recovered?.files.single.path, '/lost.jpg');
    expect(coordinator.state?.context, expected);

    await coordinator.acknowledgeRecovered(expected);
    expect(coordinator.state, isNull);
    expect(store.current, isNull);
    expect(store.recovered, isNull);

    await coordinator.initialize();
    expect(picker.retrieveLostDataCalls, 1);
  });

  test('영속 복구 결과는 두 번째 프로세스 초기화에서 플랫폼 재회수 없이 복원한다', () async {
    SharedPreferences.setMockInitialValues({});
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'body_frame_picker_persistence_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final recoveredFile = await File(
      '${temporaryDirectory.path}/recovered.jpg',
    ).writeAsBytes(const [1, 2, 3]);
    final expected = ImagePickerRequestContext.galleryImport();
    final firstStore = SharedPreferencesImagePickerRequestStore();
    await firstStore.save(expected);
    final firstPicker = FakeAppImagePicker(
      lostResponse: LostDataResponse(files: [XFile(recoveredFile.path)]),
      store: firstStore,
    );
    final firstCoordinator = AppImagePickerCoordinator(
      picker: firstPicker,
      requestStore: firstStore,
    );

    await firstCoordinator.initialize();
    expect(firstPicker.retrieveLostDataCalls, 1);
    expect((await firstStore.loadRecovered())?.context, expected);
    expect(await firstStore.load(), expected);
    firstCoordinator.dispose();

    final secondStore = SharedPreferencesImagePickerRequestStore();
    final secondPicker = FakeAppImagePicker(
      lostResponse: LostDataResponse.empty(),
      store: secondStore,
    );
    final secondCoordinator = AppImagePickerCoordinator(
      picker: secondPicker,
      requestStore: secondStore,
    );
    addTearDown(secondCoordinator.dispose);

    await secondCoordinator.initialize();

    expect(secondPicker.retrieveLostDataCalls, 0);
    expect(
      secondCoordinator.recoveredFor(expected)?.files.single.path,
      recoveredFile.path,
    );
    await secondCoordinator.acknowledgeRecovered(expected);
    expect(await secondStore.loadRecovered(), isNull);
    expect(await secondStore.load(), isNull);
  });

  test('영속 복구 파일이 사라졌으면 문맥을 정리해 새 picker를 막지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final expected = ImagePickerRequestContext.galleryImport();
    final store = SharedPreferencesImagePickerRequestStore();
    await store.save(expected);
    await store.saveRecovered(
      RecoveredImagePickerSelection(
        context: expected,
        files: [XFile('/missing/recovered.jpg')],
      ),
    );
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse.empty(),
      store: store,
      pickedFile: XFile('/new-selection.jpg'),
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);

    await coordinator.initialize();

    expect(coordinator.state, isNull);
    expect(await store.load(), isNull);
    expect(await store.loadRecovered(), isNull);
    expect(picker.retrieveLostDataCalls, 0);
    expect(
      await coordinator.pickImage(
        context: ImagePickerRequestContext.galleryImport(),
        source: ImageSource.gallery,
      ),
      isNotNull,
    );
  });

  test('삭제된 대상의 복구 결과는 사용자의 다른 새 선택으로 안전하게 대체한다', () async {
    final obsolete = ImagePickerRequestContext.photoReplacement(
      recordId: 'deleted-record',
      photoId: 'deleted-photo',
    );
    final next = ImagePickerRequestContext.galleryImport();
    final store = MemoryImagePickerRequestStore(obsolete);
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse(file: XFile('/obsolete.jpg')),
      store: store,
      pickedFile: XFile('/new-selection.jpg'),
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize();

    final picked = await coordinator.pickImage(
      context: next,
      source: ImageSource.gallery,
    );

    expect(picked?.path, '/new-selection.jpg');
    expect(coordinator.state, isNull);
    expect(store.recovered, isNull);
    expect(store.current, isNull);
    expect(picker.contextDuringPick, next);
  });

  test('플랫폼 회수 예외는 pending 문맥을 유지하고 다음 initialize에서 재시도한다', () async {
    final expected = ImagePickerRequestContext.photoReplacement(
      recordId: 'record-9',
      photoId: 'photo-9',
    );
    final store = MemoryImagePickerRequestStore(expected);
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse(
        file: XFile('/cache/replacement.jpg'),
      ),
      store: store,
    )..throwOnRetrieve = true;
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);

    await expectLater(coordinator.initialize(), throwsStateError);
    expect(store.current, expected);
    expect(store.recovered, isNull);
    expect(picker.retrieveLostDataCalls, 1);

    picker.throwOnRetrieve = false;
    await coordinator.initialize();

    expect(picker.retrieveLostDataCalls, 2);
    expect(coordinator.recoveredFor(expected)?.context, expected);
    expect(store.current, expected);
  });

  test('picker 호출 전에 문맥을 저장하고 정상 반환과 오류에서 정리한다', () async {
    final request = ImagePickerRequestContext.photoReplacement(
      recordId: 'record-1',
      photoId: 'photo-1',
    );
    final store = MemoryImagePickerRequestStore();
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse.empty(),
      store: store,
      pickedFile: XFile.fromData(
        Uint8List.fromList([4, 5, 6]),
        path: '/picked.jpg',
      ),
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);

    final picked = await coordinator.pickImage(
      context: request,
      source: ImageSource.gallery,
    );

    expect(picked?.path, '/picked.jpg');
    expect(picker.contextDuringPick, request);
    expect(store.current, isNull);

    picker.throwOnPick = true;
    await expectLater(
      coordinator.pickImage(context: request, source: ImageSource.gallery),
      throwsStateError,
    );
    expect(picker.contextDuringPick, request);
    expect(store.current, isNull);
  });

  test('다중 선택도 갤러리 대상 문맥을 먼저 저장하고 반환 후 정리한다', () async {
    final request = ImagePickerRequestContext.galleryImport();
    final store = MemoryImagePickerRequestStore();
    final picker = FakeAppImagePicker(
      lostResponse: LostDataResponse.empty(),
      store: store,
      multiFiles: [
        XFile.fromData(Uint8List.fromList([7]), path: '/one.jpg'),
      ],
    );
    final coordinator = AppImagePickerCoordinator(
      picker: picker,
      requestStore: store,
    );
    addTearDown(coordinator.dispose);

    final files = await coordinator.pickMultiImage(context: request);

    expect(files.single.path, '/one.jpg');
    expect(picker.contextDuringPick, request);
    expect(store.current, isNull);
  });
}

class MemoryImagePickerRequestStore
    implements ImagePickerRequestStore, ImagePickerRecoveryStore {
  ImagePickerRequestContext? current;
  RecoveredImagePickerSelection? recovered;

  MemoryImagePickerRequestStore([this.current]);

  @override
  Future<void> clear() async {
    current = null;
  }

  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {
    if (current == context) current = null;
  }

  @override
  Future<void> clearRecovered() async {
    recovered = null;
  }

  @override
  Future<void> clearRecoveredIfMatches(
    ImagePickerRequestContext context,
  ) async {
    if (recovered?.context == context) recovered = null;
  }

  @override
  Future<ImagePickerRequestContext?> load() async => current;

  @override
  Future<RecoveredImagePickerSelection?> loadRecovered() async => recovered;

  @override
  Future<void> save(ImagePickerRequestContext context) async {
    current = context;
  }

  @override
  Future<void> saveRecovered(RecoveredImagePickerSelection selection) async {
    recovered = selection;
  }
}

class FakeAppImagePicker implements AppImagePicker {
  LostDataResponse lostResponse;
  final ImagePickerRequestStore store;
  final XFile? pickedFile;
  final List<XFile> multiFiles;

  int retrieveLostDataCalls = 0;
  bool throwOnPick = false;
  bool throwOnRetrieve = false;
  ImagePickerRequestContext? contextDuringPick;

  FakeAppImagePicker({
    required this.lostResponse,
    required this.store,
    this.pickedFile,
    this.multiFiles = const [],
  });

  @override
  bool get supportsLostDataRecovery => true;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async {
    contextDuringPick = await store.load();
    if (throwOnPick) throw StateError('picker failure');
    return pickedFile;
  }

  @override
  Future<List<XFile>> pickMultiImage() async {
    contextDuringPick = await store.load();
    return multiFiles;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveLostDataCalls += 1;
    if (throwOnRetrieve) throw StateError('retrieve failure');
    return lostResponse;
  }
}
