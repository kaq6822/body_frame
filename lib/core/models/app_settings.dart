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

/// 촬영 편의 설정.
///
/// 기기를 거치해 놓고 혼자 전신을 찍는 것이 이 앱의 기본 사용 방식이라,
/// 셔터를 누른 뒤 물러날 시간을 주는 셀프 타이머가 사실상 필수다.
class CaptureOptions {
  /// 새 세션을 시작할 때의 셀프 타이머(초). 0이면 사용하지 않는다.
  ///
  /// 촬영 화면 상단 버튼으로 바꾼 값은 그 세션에만 적용되고, 이 값이 다음 세션의
  /// 시작값이 된다.
  final int timerSeconds;

  /// 카운트다운 중 소리·햅틱 피드백. 화면을 보고 있지 않을 때 남은 시간을 알린다.
  final bool countdownFeedback;

  const CaptureOptions({this.timerSeconds = 0, this.countdownFeedback = true});

  static const CaptureOptions defaults = CaptureOptions();

  /// 타이머가 순환하는 값. 0은 끔.
  static const List<int> timerChoices = [0, 3, 5, 10];

  /// 저장된 값이 순환 목록에 없으면 끔으로 본다.
  static int normalizeTimer(int value) =>
      timerChoices.contains(value) ? value : 0;

  CaptureOptions copyWith({int? timerSeconds, bool? countdownFeedback}) {
    return CaptureOptions(
      timerSeconds: timerSeconds ?? this.timerSeconds,
      countdownFeedback: countdownFeedback ?? this.countdownFeedback,
    );
  }

  Map<String, dynamic> toMap() => {
    'timerSeconds': timerSeconds,
    'countdownFeedback': countdownFeedback,
  };

  factory CaptureOptions.fromMap(Map<String, dynamic> map) {
    return CaptureOptions(
      timerSeconds: normalizeTimer((map['timerSeconds'] as int?) ?? 0),
      countdownFeedback: (map['countdownFeedback'] as bool?) ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureOptions &&
      other.timerSeconds == timerSeconds &&
      other.countdownFeedback == countdownFeedback;

  @override
  int get hashCode => Object.hash(timerSeconds, countdownFeedback);
}

/// 앱 전역 설정. shared_preferences에 JSON으로 영속화한다.
class AppSettings {
  /// 기본 격자 설정.
  final GridSettings defaultGrid;

  /// 기본 저장 이미지 설정.
  final ExportImageOptions defaultExportOptions;

  /// 촬영 편의 설정.
  final CaptureOptions capture;

  const AppSettings({
    this.defaultGrid = GridSettings.defaults,
    this.defaultExportOptions = ExportImageOptions.defaults,
    this.capture = CaptureOptions.defaults,
  });

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    GridSettings? defaultGrid,
    ExportImageOptions? defaultExportOptions,
    CaptureOptions? capture,
  }) {
    return AppSettings(
      defaultGrid: defaultGrid ?? this.defaultGrid,
      defaultExportOptions: defaultExportOptions ?? this.defaultExportOptions,
      capture: capture ?? this.capture,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultGrid': defaultGrid.toMap(),
      'defaultExportOptions': defaultExportOptions.toMap(),
      'capture': capture.toMap(),
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
      // 이 필드가 없던 버전의 저장값에서도 기본값으로 열린다.
      capture: map['capture'] == null
          ? CaptureOptions.defaults
          : CaptureOptions.fromMap(
              (map['capture'] as Map).cast<String, dynamic>(),
            ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AppSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return AppSettings.defaults;
    return AppSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
