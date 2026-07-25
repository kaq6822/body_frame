import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/features/members/widgets/member_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late Directory tempDirectory;
  late File existingImage;
  late File recoveredImage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'body_frame_member_avatar_recovery_',
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA'
      'ASsJTYQAAAAASUVORK5CYII=',
    );
    existingImage = await File(
      '${tempDirectory.path}/existing.png',
    ).writeAsBytes(png);
    recoveredImage = await File(
      '${tempDirectory.path}/recovered.png',
    ).writeAsBytes(png);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('다른 회원의 유실 대표 사진은 편집 폼에 적용하지 않는다', (tester) async {
    final coordinator = await _coordinatorFor(
      ImagePickerRequestContext.memberAvatar('member-2'),
      recoveredImage,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MemberFormBody(existing: _member(existingImage.path)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_avatarPath(tester), existingImage.path);
    expect(coordinator.state?.context.memberId, 'member-2');
  });

  testWidgets('정확한 회원의 유실 대표 사진은 저장하지 않고 미리보기만 바꾼다', (tester) async {
    final coordinator = await _coordinatorFor(
      ImagePickerRequestContext.memberAvatar('member-1'),
      recoveredImage,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MemberFormBody(existing: _member(existingImage.path)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_avatarPath(tester), recoveredImage.path);
    expect(coordinator.state, isNull);
    expect(find.byKey(const ValueKey('members.save.button')), findsOneWidget);
  });

  testWidgets('재시작 뒤 새 UUID를 쓰는 신규 회원 폼도 유실 대표 사진을 복구한다', (tester) async {
    final coordinator = await _coordinatorFor(
      ImagePickerRequestContext.newMemberAvatar(),
      recoveredImage,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImagePickerCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: const MaterialApp(home: Scaffold(body: MemberFormBody())),
      ),
    );
    await tester.pump();

    expect(_avatarPath(tester), recoveredImage.path);
    expect(coordinator.state, isNull);
    expect(find.byKey(const ValueKey('members.save.button')), findsOneWidget);
  });
}

Member _member(String avatarPath) => Member(
  id: 'member-1',
  name: '테스트 회원',
  avatarPath: avatarPath,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

String? _avatarPath(WidgetTester tester) {
  final avatar = tester.widget<CircleAvatar>(
    find.byKey(const ValueKey('member.avatar.image')),
  );
  final provider = avatar.backgroundImage;
  return provider is FileImage ? provider.file.path : null;
}

Future<AppImagePickerCoordinator> _coordinatorFor(
  ImagePickerRequestContext context,
  File recoveredImage,
) async {
  final coordinator = AppImagePickerCoordinator(
    picker: _LostFilePicker(recoveredImage),
    requestStore: _MemoryRequestStore(context),
  );
  await coordinator.initialize();
  return coordinator;
}

class _LostFilePicker implements AppImagePicker {
  final File file;

  _LostFilePicker(this.file);

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
