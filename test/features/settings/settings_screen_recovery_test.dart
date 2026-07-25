import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;
  late File recoveredLogo;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'body_frame_studio_logo_recovery_',
    );
    recoveredLogo = await File('${tempDirectory.path}/recovered-logo.png')
        .writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
            'ASsJTYQAAAAASUVORK5CYII=',
          ),
        );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('유실된 스튜디오 로고를 설정에 저장한 뒤 복구 결과를 확인 처리한다', (tester) async {
    final context = ImagePickerRequestContext.studioLogo();
    final store = _MemoryRequestStore(context);
    final coordinator = AppImagePickerCoordinator(
      picker: _LostLogoPicker(recoveredLogo),
      requestStore: store,
    );
    await coordinator.initialize();
    final settingsService = _MemoryAppSettingsService();
    final storage = _LogoStorage(tempDirectory);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
          appSettingsServiceProvider.overrideWithValue(settingsService),
          photoStorageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    for (
      var i = 0;
      i < 40 &&
          (settingsService.current.studioLogoPath == null ||
              coordinator.state != null);
      i += 1
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final storedPath = settingsService.current.studioLogoPath;
    expect(storedPath, startsWith('photos/studio-assets/'));
    expect(coordinator.state, isNull);
    expect(store.current, isNull);
    expect(
      File(storage.resolvePathSync(storedPath!)).readAsBytesSync(),
      orderedEquals(recoveredLogo.readAsBytesSync()),
    );
  });
}

class _MemoryAppSettingsService implements AppSettingsService {
  AppSettings current = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
  }
}

class _LogoStorage implements PhotoStorageService {
  final Directory root;

  _LogoStorage(this.root);

  @override
  Future<void> reconcilePendingQuarantines() async {}

  @override
  Future<Directory> memberDir(String memberId) async {
    final directory = Directory(p.join(root.path, 'photos', memberId));
    directory.createSync(recursive: true);
    return directory;
  }

  @override
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  }) async {
    final directory = await memberDir(memberId);
    return File(
      sourcePath,
    ).copySync(p.join(directory.path, fileName ?? p.basename(sourcePath))).path;
  }

  @override
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final directory = await memberDir(memberId);
    final file = File(p.join(directory.path, fileName));
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  @override
  Future<String> resolvePath(String storedPath) async {
    return resolvePathSync(storedPath);
  }

  String resolvePathSync(String storedPath) {
    if (p.isAbsolute(storedPath)) return storedPath;
    return p.joinAll([root.path, ...p.posix.split(storedPath)]);
  }

  @override
  Future<String> toStoredPath(String filePath) async {
    final relative = p.relative(filePath, from: root.path);
    return p.posix.joinAll(p.split(relative));
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(await resolvePath(filePath));
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> deleteMemberDir(String memberId) async {}

  @override
  Future<StorageQuarantine?> quarantineFile(String filePath) async => null;

  @override
  Future<StorageQuarantine?> quarantineMemberDir(String memberId) async => null;

  @override
  Future<void> restoreQuarantine(StorageQuarantine quarantine) async {}

  @override
  Future<void> discardQuarantine(StorageQuarantine quarantine) async {}
}

class _LostLogoPicker implements AppImagePicker {
  final File file;

  _LostLogoPicker(this.file);

  @override
  bool get supportsLostDataRecovery => true;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;

  @override
  Future<List<XFile>> pickMultiImage() async => const [];

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return LostDataResponse(file: XFile(file.path));
  }
}

class _MemoryRequestStore implements ImagePickerRequestStore {
  ImagePickerRequestContext? current;

  _MemoryRequestStore(this.current);

  @override
  Future<void> clear() async => current = null;

  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {
    if (current == context) current = null;
  }

  @override
  Future<ImagePickerRequestContext?> load() async => current;

  @override
  Future<void> save(ImagePickerRequestContext context) async {
    current = context;
  }
}
