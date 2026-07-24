import 'dart:convert';

import 'grid_settings.dart';

/// 앱 잠금 방식.
enum LockMode {
  none,
  password,
  pin,
  biometric;

  String get key => name;

  String get label {
    switch (this) {
      case LockMode.none:
        return '잠금 사용 안 함';
      case LockMode.password:
        return '비밀번호';
      case LockMode.pin:
        return 'PIN 번호';
      case LockMode.biometric:
        return '기기 생체 인증';
    }
  }

  static LockMode fromKey(String? key) {
    return LockMode.values.firstWhere(
      (m) => m.key == key,
      orElse: () => LockMode.none,
    );
  }
}

/// 비교 이미지 생성 시 포함 항목.
class ExportImageOptions {
  final bool includeMemberName;
  final bool includeShotDate;
  final bool includeMemo;
  final bool includeGrid;
  final bool includeStudioName;
  final bool includeWatermark;

  const ExportImageOptions({
    // 개인정보 보호를 위해 회원 이름은 기본 숨김.
    this.includeMemberName = false,
    this.includeShotDate = true,
    this.includeMemo = false,
    this.includeGrid = false,
    this.includeStudioName = true,
    this.includeWatermark = true,
  });

  static const ExportImageOptions defaults = ExportImageOptions();

  ExportImageOptions copyWith({
    bool? includeMemberName,
    bool? includeShotDate,
    bool? includeMemo,
    bool? includeGrid,
    bool? includeStudioName,
    bool? includeWatermark,
  }) {
    return ExportImageOptions(
      includeMemberName: includeMemberName ?? this.includeMemberName,
      includeShotDate: includeShotDate ?? this.includeShotDate,
      includeMemo: includeMemo ?? this.includeMemo,
      includeGrid: includeGrid ?? this.includeGrid,
      includeStudioName: includeStudioName ?? this.includeStudioName,
      includeWatermark: includeWatermark ?? this.includeWatermark,
    );
  }

  Map<String, dynamic> toMap() => {
        'includeMemberName': includeMemberName,
        'includeShotDate': includeShotDate,
        'includeMemo': includeMemo,
        'includeGrid': includeGrid,
        'includeStudioName': includeStudioName,
        'includeWatermark': includeWatermark,
      };

  factory ExportImageOptions.fromMap(Map<String, dynamic> map) {
    return ExportImageOptions(
      includeMemberName: (map['includeMemberName'] as bool?) ?? false,
      includeShotDate: (map['includeShotDate'] as bool?) ?? true,
      includeMemo: (map['includeMemo'] as bool?) ?? false,
      includeGrid: (map['includeGrid'] as bool?) ?? false,
      includeStudioName: (map['includeStudioName'] as bool?) ?? true,
      includeWatermark: (map['includeWatermark'] as bool?) ?? true,
    );
  }
}

/// 앱 전역 설정.
///
/// shared_preferences에 JSON으로 영속화한다. 잠금 비밀번호/PIN 자체는
/// 여기에 저장하지 않고 flutter_secure_storage에 보관한다.
class AppSettings {
  /// 앱 잠금 방식.
  final LockMode lockMode;

  /// 생체 인증 사용 여부.
  final bool biometricEnabled;

  /// 자동 잠금 시간(초). 0이면 자동 잠금 사용 안 함.
  final int autoLockSeconds;

  /// 기본 격자 설정.
  final GridSettings defaultGrid;

  /// 기본 저장 이미지 설정.
  final ExportImageOptions defaultExportOptions;

  /// 스튜디오명 (선택).
  final String? studioName;

  /// 스튜디오 로고 로컬 파일 경로 (선택).
  final String? studioLogoPath;

  /// 앱 삭제 시 데이터 삭제 안내 확인 여부(최초 안내 노출 제어).
  final bool dataNoticeAcknowledged;

  const AppSettings({
    this.lockMode = LockMode.none,
    this.biometricEnabled = false,
    this.autoLockSeconds = 0,
    this.defaultGrid = GridSettings.defaults,
    this.defaultExportOptions = ExportImageOptions.defaults,
    this.studioName,
    this.studioLogoPath,
    this.dataNoticeAcknowledged = false,
  });

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    LockMode? lockMode,
    bool? biometricEnabled,
    int? autoLockSeconds,
    GridSettings? defaultGrid,
    ExportImageOptions? defaultExportOptions,
    String? studioName,
    String? studioLogoPath,
    bool? dataNoticeAcknowledged,
  }) {
    return AppSettings(
      lockMode: lockMode ?? this.lockMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      defaultGrid: defaultGrid ?? this.defaultGrid,
      defaultExportOptions: defaultExportOptions ?? this.defaultExportOptions,
      studioName: studioName ?? this.studioName,
      studioLogoPath: studioLogoPath ?? this.studioLogoPath,
      dataNoticeAcknowledged:
          dataNoticeAcknowledged ?? this.dataNoticeAcknowledged,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lockMode': lockMode.key,
      'biometricEnabled': biometricEnabled,
      'autoLockSeconds': autoLockSeconds,
      'defaultGrid': defaultGrid.toMap(),
      'defaultExportOptions': defaultExportOptions.toMap(),
      'studioName': studioName,
      'studioLogoPath': studioLogoPath,
      'dataNoticeAcknowledged': dataNoticeAcknowledged,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      lockMode: LockMode.fromKey(map['lockMode'] as String?),
      biometricEnabled: (map['biometricEnabled'] as bool?) ?? false,
      autoLockSeconds: (map['autoLockSeconds'] as int?) ?? 0,
      defaultGrid: map['defaultGrid'] == null
          ? GridSettings.defaults
          : GridSettings.fromMap(
              (map['defaultGrid'] as Map).cast<String, dynamic>()),
      defaultExportOptions: map['defaultExportOptions'] == null
          ? ExportImageOptions.defaults
          : ExportImageOptions.fromMap(
              (map['defaultExportOptions'] as Map).cast<String, dynamic>()),
      studioName: map['studioName'] as String?,
      studioLogoPath: map['studioLogoPath'] as String?,
      dataNoticeAcknowledged:
          (map['dataNoticeAcknowledged'] as bool?) ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AppSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return AppSettings.defaults;
    return AppSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
