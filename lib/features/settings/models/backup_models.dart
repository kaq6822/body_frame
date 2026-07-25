/// 백업 대상 범위.
enum BackupScope { all, member }

/// 복원 모드(교체 또는 추가).
///
/// 회원별 백업은 다른 회원의 데이터 손실을 막기 위해 [append]만 허용한다.
enum RestoreMode { replace, append }

/// 백업 zip 내부 `data.json` 스키마 버전.
///
/// v2부터 실제 촬영 격자 설정을 앱 설정과 별도로 저장한다. v1 백업은
/// [BackupService.prepareRestore]에서 계속 읽을 수 있다.
const int backupFormatVersion = 2;
const int legacyBackupFormatVersion = 1;

/// 신뢰되지 않은 ZIP을 메모리와 임시 저장소에 풀 때 적용하는 상한.
///
/// 테스트에서는 작은 값을 주입해 큰 파일을 실제로 만들지 않고도 제한 동작을
/// 검증할 수 있다.
class BackupArchiveLimits {
  final int maxCompressedBytes;
  final int maxEntryCount;
  final int maxDataJsonBytes;
  final int maxSingleFileBytes;
  final int maxTotalUncompressedBytes;
  final int maxPathLength;

  const BackupArchiveLimits({
    this.maxCompressedBytes = 512 * 1024 * 1024,
    this.maxEntryCount = 10000,
    this.maxDataJsonBytes = 4 * 1024 * 1024,
    this.maxSingleFileBytes = 100 * 1024 * 1024,
    this.maxTotalUncompressedBytes = 2 * 1024 * 1024 * 1024,
    this.maxPathLength = 512,
  });
}

/// 사용자가 선택한 복원 파일을 메모리에 읽기 전에 적용할 입력 크기 계약.
///
/// legacy ZIP과 암호화 컨테이너는 컨테이너 오버헤드 때문에 허용 크기가 다르다.
/// 화면은 파일 확장자에 맞는 상한을 사용하고, 형식을 특정할 수 없을 때만 두
/// 형식 중 큰 상한인 [maximumFileBytes]를 사용한다. 실제 내용 형식은 이후
/// 서비스가 별도로 검증한다.
class BackupRestoreInputLimits {
  final int maximumLegacyZipBytes;
  final int maximumEncryptedContainerBytes;

  const BackupRestoreInputLimits({
    required this.maximumLegacyZipBytes,
    required this.maximumEncryptedContainerBytes,
  }) : assert(maximumLegacyZipBytes > 0),
       assert(maximumEncryptedContainerBytes > 0);

  int get maximumFileBytes =>
      maximumLegacyZipBytes > maximumEncryptedContainerBytes
      ? maximumLegacyZipBytes
      : maximumEncryptedContainerBytes;
}

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
  final Map<String, dynamic>? rawGridSettings;

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
    required this.rawGridSettings,
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
