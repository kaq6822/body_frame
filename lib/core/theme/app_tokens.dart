import 'package:flutter/material.dart';

/// 간격 스케일(4배수).
///
/// 앱은 이미 사실상 4배수를 쓰고 있어 이름만 붙인다. 스케일 밖 값이 필요해 보이면
/// 먼저 인접한 두 단계로 표현할 수 없는지 검토한다.
abstract final class AppSpacing {
  /// 4 — 라벨 ↔ 입력, 아이콘 ↔ 짧은 라벨.
  static const double sp1 = 4;

  /// 8 — 목록 항목 간, 칩 간.
  static const double sp2 = 8;

  /// 12 — 타일 내부 세로 패딩.
  static const double sp3 = 12;

  /// 16 — 화면 가로 여백, 카드 내부.
  static const double sp4 = 16;

  /// 20 — 기본 선택지가 아니다. sp4 또는 sp6을 먼저 검토한다.
  static const double sp5 = 20;

  /// 24 — 섹션 간, 빈 상태 여백.
  static const double sp6 = 24;

  /// 32 — 구분선을 포함한 섹션 경계.
  static const double sp7 = 32;

  /// 40 — 화면 최상단·최하단 여유.
  static const double sp8 = 40;

  /// 최소 터치 타겟. Material 접근성 기준.
  static const double minTouchTarget = 48;

  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: sp4,
  );

  static const EdgeInsets content = EdgeInsets.all(sp4);
}

/// 라운딩 스케일.
///
/// BodyMark는 각진 계측 도구의 인상을 유지한다. 완전 둥근 모양은 작은 상태 칩에만
/// 쓴다. 그림자 대신 1px 테두리로 면을 구분한다.
abstract final class AppRadius {
  /// 4 — 배지, 색 스와치.
  static const double xs = 4;

  /// 6 — 버튼, 썸네일, 작은 조작부.
  static const double sm = 6;

  /// 8 — 카드, 입력, 사진 프레임. 사진 프레임은 이 값을 넘기지 않는다. 라운딩이
  /// 커지면 letterbox 여백 모서리에서 사진이 잘려 보인다.
  static const double md = 8;

  /// 12 — 다이얼로그, 바텀시트 상단.
  static const double lg = 12;

  /// 16 — 화면 상단 안내 패널처럼 넓은 면. 기본 선택지가 아니다.
  static const double xl = 16;

  /// 완전 둥근 모서리 — 상태 pill, HUD 칩.
  static const double full = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));
}

/// M3 [ColorScheme]에 없는 상태 색.
///
/// `context.semanticColors`로 읽는다.
///
/// - `warning`은 **텍스트·아이콘용** 진한 앰버다. 밝은 면에서 4.5:1을 넘긴다.
/// - `warningFill`은 기울기 경고처럼 면·선으로 칠하는 앰버(`#F59E0B`)다. 흰
///   글자를 올리지 않는다.
/// - `measure`는 측정·가이드 전용 시안(`#06B6D4`)이다. 수평 잠금, 촬영 가이드,
///   카메라 안 활성 방향처럼 "기준에 맞았다"는 신호에만 쓴다. 밝은 면에서 텍스트
///   색으로 쓰지 않는다(대비 부족). 그 위의 글자는 `onMeasure`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.warningFill,
    required this.measure,
    required this.onMeasure,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color warningFill;
  final Color measure;
  final Color onMeasure;

  static const light = AppSemanticColors(
    success: Color(0xFF15803D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    warningFill: Color(0xFFF59E0B),
    measure: Color(0xFF06B6D4),
    onMeasure: Color(0xFF082F49),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF14532D),
    onSuccessContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF451A03),
    warningContainer: Color(0xFF78350F),
    onWarningContainer: Color(0xFFFEF3C7),
    warningFill: Color(0xFFF59E0B),
    measure: Color(0xFF06B6D4),
    onMeasure: Color(0xFF082F49),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? warningFill,
    Color? measure,
    Color? onMeasure,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      warningFill: warningFill ?? this.warningFill,
      measure: measure ?? this.measure,
      onMeasure: onMeasure ?? this.onMeasure,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      success: mix(success, other.success),
      onSuccess: mix(onSuccess, other.onSuccess),
      successContainer: mix(successContainer, other.successContainer),
      onSuccessContainer: mix(onSuccessContainer, other.onSuccessContainer),
      warning: mix(warning, other.warning),
      onWarning: mix(onWarning, other.onWarning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      warningFill: mix(warningFill, other.warningFill),
      measure: mix(measure, other.measure),
      onMeasure: mix(onMeasure, other.onMeasure),
    );
  }
}

/// 사진 표시 영역 전용 색. **라이트/다크에서 같은 값을 쓴다.**
///
/// 체형 사진은 원본 비율과 방향을 보존해 표시하므로 프레임에 letterbox 여백이
/// 생긴다. 그 여백과 사진 위 컨트롤에 색이 개입하면 피부톤·명암 판단이 흐려지고,
/// 스킴에 따라 값이 바뀌면 같은 사진이 다르게 보인다. 촬영·비교·내보내기 세 경로가
/// 같은 값을 써야 한다.
@immutable
class AppPhotoColors extends ThemeExtension<AppPhotoColors> {
  const AppPhotoColors();

  /// 사진 프레임의 letterbox 여백.
  Color get backdrop => const Color(0xFF101114);

  /// 프레임 안쪽 옅은 음영.
  Color get inset => const Color(0x14000000);

  /// 사진 위 컨트롤 바 배경.
  Color get chrome => const Color(0x9E000000);

  /// 사진 위 패널 배경(컨트롤 바보다 진하게).
  ///
  /// 컨트롤 바보다 훨씬 불투명하다. 패널에는 라벨과 수치가 들어가는데, 밝은 장면을
  /// 비추는 뷰파인더 위에서 반투명 배경을 쓰면 흰 글자의 대비가 4.5:1 아래로
  /// 떨어진다. 배경을 거의 불투명하게 두어 대비가 장면에 좌우되지 않게 한다.
  Color get panel => const Color(0xF2000000);

  /// 사진 위 상단 그라데이션 시작색(끝은 투명).
  Color get chromeGradientTop => const Color(0x8C000000);

  /// 사진 위 텍스트·아이콘. 계층은 이 값을 흐리지 않고 배경 불투명도로 만든다.
  /// 전경을 흐리면 밝은 사진 위에서 대비가 4.5:1 아래로 떨어진다.
  Color get onChrome => const Color(0xFFFFFFFF);

  /// 사진 위 아이콘 버튼 배경(선택 상태).
  Color get controlFill => const Color(0x38FFFFFF);

  /// 사진 위 컨트롤 외곽선(비선택 상태).
  Color get controlOutline => const Color(0x59FFFFFF);

  /// 사진 위 컨트롤 트랙(슬라이더 비활성 구간).
  Color get controlTrack => const Color(0x40FFFFFF);

  /// 카메라 뷰파인더 바탕(사진 영역 밖 촬영 화면 전체).
  Color get viewfinder => const Color(0xFF090D14);

  /// 카메라 위 떠 있는 HUD 컨트롤 면. slate 900 78%.
  Color get hudSurface => const Color(0xC70F172A);

  /// HUD 컨트롤의 1px 외곽선. 흰색 16%.
  Color get hudOutline => const Color(0x29FFFFFF);

  /// 측정·가이드 시안. 수평 잠금, 기준선, 카메라 안 활성 방향.
  /// [AppSemanticColors.measure]와 같은 값이다.
  Color get measure => const Color(0xFF06B6D4);

  /// [measure] 면 위 글자·아이콘. 흰색은 시안 위에서 대비가 부족하다.
  Color get onMeasure => const Color(0xFF082F49);

  /// 거의 수평·기울기 경고 앰버. 사진 위 선·면 전용.
  Color get warning => const Color(0xFFF59E0B);

  @override
  AppPhotoColors copyWith() => const AppPhotoColors();

  /// 스킴 간 보간이 없다. 라이트/다크가 같은 값이므로 항상 자신을 반환한다.
  @override
  AppPhotoColors lerp(ThemeExtension<AppPhotoColors>? other, double t) => this;
}

/// 날짜·시각·건수·용량·각도용 파생 텍스트 스타일(tabular figures).
///
/// 목록에서 수치가 세로로 나열되므로 글자 폭이 흔들리면 열이 어긋나 보인다.
@immutable
class AppNumericTextStyles extends ThemeExtension<AppNumericTextStyles> {
  const AppNumericTextStyles({
    required this.bodySmall,
    required this.bodyMedium,
    required this.labelSmall,
    required this.labelLarge,
    required this.titleMedium,
    required this.headlineSmall,
  });

  final TextStyle bodySmall;
  final TextStyle bodyMedium;
  final TextStyle labelSmall;

  /// 각도·수치 판독(DESIGN.md data-mono 14/600).
  final TextStyle labelLarge;
  final TextStyle titleMedium;
  final TextStyle headlineSmall;

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// 기존 [TextTheme]에서 파생한다. 스케일을 다시 정의하지 않는다.
  factory AppNumericTextStyles.from(TextTheme textTheme) {
    TextStyle tabular(TextStyle? base) =>
        (base ?? const TextStyle()).copyWith(fontFeatures: _tabular);
    return AppNumericTextStyles(
      bodySmall: tabular(textTheme.bodySmall),
      bodyMedium: tabular(textTheme.bodyMedium),
      labelSmall: tabular(textTheme.labelSmall),
      labelLarge: tabular(textTheme.labelLarge),
      titleMedium: tabular(textTheme.titleMedium),
      headlineSmall: tabular(textTheme.headlineSmall),
    );
  }

  @override
  AppNumericTextStyles copyWith({
    TextStyle? bodySmall,
    TextStyle? bodyMedium,
    TextStyle? labelSmall,
    TextStyle? labelLarge,
    TextStyle? titleMedium,
    TextStyle? headlineSmall,
  }) {
    return AppNumericTextStyles(
      bodySmall: bodySmall ?? this.bodySmall,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      labelLarge: labelLarge ?? this.labelLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      headlineSmall: headlineSmall ?? this.headlineSmall,
    );
  }

  @override
  AppNumericTextStyles lerp(
    ThemeExtension<AppNumericTextStyles>? other,
    double t,
  ) {
    if (other is! AppNumericTextStyles) return this;
    return AppNumericTextStyles(
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      labelSmall: TextStyle.lerp(labelSmall, other.labelSmall, t)!,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t)!,
      titleMedium: TextStyle.lerp(titleMedium, other.titleMedium, t)!,
      headlineSmall: TextStyle.lerp(headlineSmall, other.headlineSmall, t)!,
    );
  }
}

/// 명시적 [ColorScheme].
///
/// 딥 슬레이트 시안 `#0E7490`을 주요 조작에, slate 뉴트럴을 면·글자·테두리에 쓴다.
/// 측정용 시안 `#06B6D4`는 [AppSemanticColors.measure]로만 노출한다. tertiary는
/// 용도가 없어 secondary와 같은 slate 계열로 둔다. 다크 모드는 같은 관계를 slate
/// 900 바탕 위에서 유지한다. 사진 영역에는 이 팔레트를 적용하지 않는다.
///
/// `outline`은 테두리 전용(`#CBD5E1`)이라 글자 색으로 쓰지 않는다. 보조 글자는
/// `onSurfaceVariant`(`#475569`)를 쓴다.
abstract final class AppColorSchemes {
  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0E7490),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0F2FE),
    onPrimaryContainer: Color(0xFF164E63),
    secondary: Color(0xFF475569),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF1F5F9),
    onSecondaryContainer: Color(0xFF334155),
    tertiary: Color(0xFF475569),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF1F5F9),
    onTertiaryContainer: Color(0xFF334155),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFF8FAFC),
    onSurface: Color(0xFF0F172A),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F5F9),
    surfaceContainer: Color(0xFFF1F5F9),
    surfaceContainerHigh: Color(0xFFE9EEF4),
    surfaceContainerHighest: Color(0xFFE2E8F0),
    onSurfaceVariant: Color(0xFF475569),
    outline: Color(0xFFCBD5E1),
    outlineVariant: Color(0xFFE2E8F0),
    inverseSurface: Color(0xFF1E293B),
    onInverseSurface: Color(0xFFF1F5F9),
    inversePrimary: Color(0xFF7DD3E8),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF0F172A),
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF7DD3E8),
    onPrimary: Color(0xFF083344),
    primaryContainer: Color(0xFF155E75),
    onPrimaryContainer: Color(0xFFCFFAFE),
    secondary: Color(0xFFCBD5E1),
    onSecondary: Color(0xFF1E293B),
    secondaryContainer: Color(0xFF334155),
    onSecondaryContainer: Color(0xFFE2E8F0),
    tertiary: Color(0xFFCBD5E1),
    onTertiary: Color(0xFF1E293B),
    tertiaryContainer: Color(0xFF334155),
    onTertiaryContainer: Color(0xFFE2E8F0),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF0F172A),
    onSurface: Color(0xFFF1F5F9),
    surfaceContainerLowest: Color(0xFF1E293B),
    surfaceContainerLow: Color(0xFF162033),
    surfaceContainer: Color(0xFF1E293B),
    surfaceContainerHigh: Color(0xFF273449),
    surfaceContainerHighest: Color(0xFF334155),
    onSurfaceVariant: Color(0xFF94A3B8),
    outline: Color(0xFF475569),
    outlineVariant: Color(0xFF334155),
    inverseSurface: Color(0xFFE2E8F0),
    onInverseSurface: Color(0xFF1E293B),
    inversePrimary: Color(0xFF0E7490),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
  );

  /// 주요 버튼 눌림 색. M3 기본 오버레이 대신 지정한 한 단계 진한 톤을 쓴다.
  static Color pressedPrimary(Brightness brightness) =>
      brightness == Brightness.light
      ? const Color(0xFF155E75)
      : const Color(0xFFA5E4F3);
}

/// 호출부에서 `Theme.of(context).extension<...>()!`를 반복하지 않게 한다.
extension AppThemeAccess on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;

  /// success / warning / measure.
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.light;

  /// 사진 서페이스. 스킴에 따라 바뀌지 않는다.
  AppPhotoColors get photoColors =>
      Theme.of(this).extension<AppPhotoColors>() ?? const AppPhotoColors();

  /// 날짜·건수·용량용 tabular 스타일.
  AppNumericTextStyles get numericTexts =>
      Theme.of(this).extension<AppNumericTextStyles>() ??
      AppNumericTextStyles.from(Theme.of(this).textTheme);
}
