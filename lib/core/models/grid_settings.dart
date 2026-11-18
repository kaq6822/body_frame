import 'dart:convert';

/// 촬영/비교 화면에서 사용하는 격자 설정.
///
/// 표시 여부, 투명도, 선 굵기, 간격, 색상을 조절한다.
/// BodyPhoto에는 촬영 당시의 격자 설정을 JSON으로 함께 저장한다.
class GridSettings {
  /// 격자 표시 여부.
  final bool visible;

  /// 투명도 0.0(투명) ~ 1.0(불투명).
  final double opacity;

  /// 선 굵기(논리 픽셀).
  final double lineWidth;

  /// 격자 칸 간격(논리 픽셀).
  final double spacing;

  /// 선 색상 (ARGB 32비트 정수).
  final int colorValue;

  /// 기본값은 자세 평가에 맞춘 성긴 격자다(360dp 폭 ≈ 6칸, 투명도 40%).
  /// 수직 기준선(다림줄)이 핵심이라 촘촘한 격자는 피사체만 가린다.
  /// 저장된 사용자 설정·사진별 격자 기록은 그대로 두고 기본값만 바꾼다.
  const GridSettings({
    this.visible = true,
    this.opacity = 0.4,
    this.lineWidth = 1.0,
    this.spacing = 60.0,
    this.colorValue = 0xFFFFFFFF,
  });

  /// 설정 초기화용 기본값.
  static const GridSettings defaults = GridSettings();

  GridSettings copyWith({
    bool? visible,
    double? opacity,
    double? lineWidth,
    double? spacing,
    int? colorValue,
  }) {
    return GridSettings(
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      lineWidth: lineWidth ?? this.lineWidth,
      spacing: spacing ?? this.spacing,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'visible': visible,
      'opacity': opacity,
      'lineWidth': lineWidth,
      'spacing': spacing,
      'colorValue': colorValue,
    };
  }

  factory GridSettings.fromMap(Map<String, dynamic> map) {
    return GridSettings(
      visible: (map['visible'] as bool?) ?? true,
      opacity: (map['opacity'] as num?)?.toDouble() ?? defaults.opacity,
      lineWidth: (map['lineWidth'] as num?)?.toDouble() ?? defaults.lineWidth,
      spacing: (map['spacing'] as num?)?.toDouble() ?? defaults.spacing,
      colorValue: (map['colorValue'] as int?) ?? 0xFFFFFFFF,
    );
  }

  /// BodyPhoto의 격자 설정 컬럼에 저장할 JSON 문자열.
  String toJson() => jsonEncode(toMap());

  factory GridSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return GridSettings.defaults;
    return GridSettings.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) =>
      other is GridSettings &&
      other.visible == visible &&
      other.opacity == opacity &&
      other.lineWidth == lineWidth &&
      other.spacing == spacing &&
      other.colorValue == colorValue;

  @override
  int get hashCode =>
      Object.hash(visible, opacity, lineWidth, spacing, colorValue);
}
