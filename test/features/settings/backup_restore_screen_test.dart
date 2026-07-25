import 'dart:typed_data';

import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/features/settings/backup_restore_screen.dart';
import 'package:body_frame/features/settings/models/backup_models.dart';
import 'package:body_frame/features/settings/providers/settings_providers.dart';
import 'package:body_frame/features/settings/services/backup_archive_cipher.dart';
import 'package:body_frame/features/settings/services/backup_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('백업 생성 전에 비밀번호와 확인값을 검증하고 obscured 입력을 사용한다', (tester) async {
    final service = _RecordingBackupService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(service),
          backupMemberListProvider.overrideWith(
            (ref) async => <MemberListItem>[],
          ),
        ],
        child: const MaterialApp(home: BackupRestoreScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('backup.create.button')));
    await tester.pumpAndSettle();

    final passwordField = find.byKey(
      const ValueKey('backup.password.create.field'),
    );
    final confirmationField = find.byKey(
      const ValueKey('backup.password.confirm.field'),
    );
    expect(passwordField, findsOneWidget);
    expect(confirmationField, findsOneWidget);
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    expect(tester.widget<TextField>(confirmationField).obscureText, isTrue);

    await tester.enterText(passwordField, 'too-short');
    await tester.enterText(confirmationField, 'too-short');
    await tester.tap(
      find.byKey(const ValueKey('backup.password.create.confirm')),
    );
    await tester.pump();
    expect(find.textContaining('12자 이상'), findsWidgets);
    expect(service.lastPassword, isNull);

    await tester.enterText(passwordField, 'correct horse battery staple');
    await tester.enterText(confirmationField, 'different password value');
    await tester.tap(
      find.byKey(const ValueKey('backup.password.create.confirm')),
    );
    await tester.pump();
    expect(find.text('비밀번호가 일치하지 않습니다'), findsOneWidget);
    expect(service.lastPassword, isNull);

    await tester.enterText(confirmationField, 'correct horse battery staple');
    await tester.tap(
      find.byKey(const ValueKey('backup.password.create.confirm')),
    );
    // 백업 생성 후에는 진행 표시가 계속 애니메이션될 수 있으므로 고정 시간만
    // 진행해 대화상자 반환과 서비스 호출을 확인한다.
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.lastPassword, 'correct horse battery staple');
  });

  testWidgets('허용 상한보다 큰 복원 파일은 바이트를 읽거나 서비스를 호출하기 전에 거부한다', (tester) async {
    final service = _RecordingBackupService();
    final oversizedFiles = [
      _TrackingXFile(
        path: '/oversized.zip',
        reportedLength: service.restoreInputLimits.maximumLegacyZipBytes + 1,
      ),
      _TrackingXFile(
        path: '/oversized.bfbackup',
        reportedLength:
            service.restoreInputLimits.maximumEncryptedContainerBytes + 1,
      ),
    ];

    for (final oversizedFile in oversizedFiles) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupServiceProvider.overrideWithValue(service),
            backupMemberListProvider.overrideWith(
              (ref) async => <MemberListItem>[],
            ),
          ],
          child: MaterialApp(
            home: BackupRestoreScreen(
              restoreFilePicker: () async => oversizedFile,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('backup.restore.button')));
      await tester.pump();

      expect(find.text('백업 파일이 허용 크기를 초과했습니다'), findsOneWidget);
      expect(oversizedFile.wasRead, isFalse);
    }
    expect(service.prepareRestoreCallCount, 0);
  });
}

class _RecordingBackupService implements BackupService {
  String? lastPassword;
  int prepareRestoreCallCount = 0;

  @override
  late final BackupRestoreInputLimits restoreInputLimits =
      _productionRestoreInputLimits();

  @override
  Future<Uint8List> buildBackup({
    String? memberId,
    required String password,
  }) async {
    lastPassword = password;
    // 임시 파일 쓰기가 플랫폼 플러그인 부재로 실패해도 화면이 일반 오류로 처리한다.
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  bool isEncryptedBackup(List<int> bytes) => false;

  @override
  Future<RestorePreview> prepareRestore(
    Uint8List backupBytes, {
    String? password,
  }) {
    prepareRestoreCallCount++;
    throw UnimplementedError();
  }

  @override
  Future<BackupOutcome> applyRestore(
    RestorePreview preview, {
    required RestoreMode mode,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanupStaleRestoreDirectories() async {}

  @override
  Future<void> discardRestore(RestorePreview preview) async {}
}

BackupRestoreInputLimits _productionRestoreInputLimits() {
  const archiveLimits = BackupArchiveLimits();
  final cipher = BackupArchiveCipherImpl(
    maxPlaintextBytes: archiveLimits.maxCompressedBytes,
  );
  return BackupRestoreInputLimits(
    maximumLegacyZipBytes: archiveLimits.maxCompressedBytes,
    maximumEncryptedContainerBytes: cipher
        .maximumContainerBytesForPlaintextLimit(
          archiveLimits.maxCompressedBytes,
        ),
  );
}

class _TrackingXFile extends XFile {
  bool wasRead = false;

  _TrackingXFile({required String path, required int reportedLength})
    : super.fromData(Uint8List(0), path: path, length: reportedLength);

  @override
  Future<Uint8List> readAsBytes() {
    wasRead = true;
    return super.readAsBytes();
  }
}
