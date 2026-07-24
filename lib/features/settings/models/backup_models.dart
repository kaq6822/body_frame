/// 백업 대상 범위.
enum BackupScope { all, member }

/// 복원 모드(교체 또는 추가).
enum RestoreMode { replace, append }

/// 백업 zip 내부 `data.json` 스키마 버전.
const int backupFormatVersion = 1;

/// [BackupService.prepareRestore]의 결과.
///
/// zip은 [tempDirPath]에 이미 추출·검증되어 있으며, 실제 DB/저장소는 아직
/// 건드리지 않은 상태다. 사용자가 모드를 확인하면 [BackupService.applyRestore]로
/// 적용하고, 취소하면 [BackupService.discardRestore]로 임시 파일을 정리한다.
class RestorePreview {
  final String tempDirPath;
  final int formatVersion;
  final BackupScope scope;
  final int memberCount;
  final int recordCount;
  final int photoCount;

  /// 복원 대상 회원 중 기존 앱에 이미 존재하는 id 집합(중복 안내용).
  final Set<String> duplicateMemberIds;

  final List<Map<String, dynamic>> rawMembers;
  final List<Map<String, dynamic>> rawRecords;
  final List<Map<String, dynamic>> rawPhotos;
  final Map<String, dynamic>? rawSettings;

  const RestorePreview({
    required this.tempDirPath,
    required this.formatVersion,
    required this.scope,
    required this.memberCount,
    required this.recordCount,
    required this.photoCount,
    required this.duplicateMemberIds,
    required this.rawMembers,
    required this.rawRecords,
    required this.rawPhotos,
    required this.rawSettings,
  });

  bool get hasDuplicates => duplicateMemberIds.isNotEmpty;
}

/// 백업/복원 적용 결과 요약.
class BackupOutcome {
  final bool success;
  final int memberCount;
  final int recordCount;
  final int photoCount;
  final String? error;

  const BackupOutcome({
    required this.success,
    this.memberCount = 0,
    this.recordCount = 0,
    this.photoCount = 0,
    this.error,
  });
}
