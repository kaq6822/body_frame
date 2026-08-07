import 'dart:convert';

import 'grid_settings.dart';

/// 비교 이미지 생성 시 포함 항목.
class ExportImageOptions {
  final bool includeShotDate;
  final bool includeLabel;
  final bool includeMemo;
  final bool includeGrid;

  const ExportImageOptions({
    this.includeShotDate = true,
    this.includeLabel = true,
    this.includeMemo = false,
    this.includeGrid = false,
  });

  static const ExportImageOptions defaults = ExportImageOptions();

  ExportImageOptions copyWith({
    bool? includeShotDate,
    bool? includeLabel,
    bool? includeMemo,
    bool? includeGrid,
  }) {
    return ExportImageOptions(
      includeShotDate: includeShotDate ?? this.includeShotDate,
      includeLabel: includeLabel ?? this.includeLabel,
      includeMemo: includeMemo ?? this.includeMemo,
      includeGrid: includeGrid ?? this.includeGrid,
    );
  }

  Map<String, dynamic> toMap() => {
    'includeShotDate': includeShotDate,
    'includeLabel': includeLabel,
    'includeMemo': includeMemo,
    'includeGrid': includeGrid,
  };

  factory ExportImageOptions.fromMap(Map<String, dynamic> map) {
    return ExportImageOptions(
      includeShotDate: (map['includeShotDate'] as bool?) ?? true,
      includeLabel: (map['includeLabel'] as bool?) ?? true,
      includeMemo: (map['includeMemo'] as bool?) ?? false,
      includeGrid: (map['includeGrid'] as bool?) ?? false,
    );
  }
}

/// 앱 전역 설정. shared_preferences에 JSON으로 영속화한다.
class AppSettings {
  /// 기본 격자 설정.
  final GridSettings defaultGrid;

  /// 기본 저장 이미지 설정.
  final ExportImageOptions defaultExportOptions;

  const AppSettings({
    this.defaultGrid = GridSettings.defaults,
    this.defaultExportOptions = ExportImageOptions.defaults,
  });

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    GridSettings? defaultGrid,
    ExportImageOptions? defaultExportOptions,
  }) {
    return AppSettings(
      defaultGrid: defaultGrid ?? this.defaultGrid,
      defaultExportOptions: defaultExportOptions ?? this.defaultExportOptions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultGrid': defaultGrid.toMap(),
      'defaultExportOptions': defaultExportOptions.toMap(),
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultGrid: map['defaultGrid'] == null
          ? GridSettings.defaults
          : GridSettings.fromMap(
              (map['defaultGrid'] as Map).cast<String, dynamic>(),
            ),
      defaultExportOptions: map['defaultExportOptions'] == null
          ? ExportImageOptions.defaults
          : ExportImageOptions.fromMap(
              (map['defaultExportOptions'] as Map).cast<String, dynamic>(),
            ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AppSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return AppSettings.defaults;
    return AppSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
