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
abstract final class AppRadius {
  /// 4 — 배지, 색 스와치.
  static const double xs = 4;

  /// 8 — 입력, 썸네일, 칩.
  static const double sm = 8;

  /// 12 — 카드, 사진 프레임. 사진 프레임은 이 값을 넘기지 않는다. 라운딩이 커지면
  /// letterbox 여백 모서리에서 사진이 잘려 보인다.
  static const double md = 12;

  /// 16 — 다이얼로그.
  static const double lg = 16;

  /// 24 — 바텀시트 상단.
  static const double xl = 24;

  /// 완전 둥근 모서리 — 버튼, 방향 칩, FAB.
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
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  static const light = AppSemanticColors(
    success: Color(0xFF1E7A4B),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFC6F0D6),
    onSuccessContainer: Color(0xFF0A3D24),
    warning: Color(0xFF8A5300),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFDFA8),
    onWarningContainer: Color(0xFF4A2C00),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF8FDCB0),
    onSuccess: Color(0xFF0A3D24),
    successContainer: Color(0xFF155C37),
    onSuccessContainer: Color(0xFFC6F0D6),
    warning: Color(0xFFF5C169),
    onWarning: Color(0xFF4A2C00),
    warningContainer: Color(0xFF6B3F00),
    onWarningContainer: Color(0xFFFFDFA8),
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
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
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

  @override
  AppPhotoColors copyWith() => const AppPhotoColors();

  /// 스킴 간 보간이 없다. 라이트/다크가 같은 값이므로 항상 자신을 반환한다.
  @override
  AppPhotoColors lerp(ThemeExtension<AppPhotoColors>? other, double t) => this;
}

/// 날짜·건수·용량용 파생 텍스트 스타일.
///
/// 목록에서 수치가 세로로 나열되므로 글자 폭이 흔들리면 열이 어긋나 보인다.
@immutable
class AppNumericTextStyles extends ThemeExtension<AppNumericTextStyles> {
  const AppNumericTextStyles({
    required this.bodySmall,
    required this.bodyMedium,
    required this.labelSmall,
    required this.titleMedium,
    required this.headlineSmall,
  });

  final TextStyle bodySmall;
  final TextStyle bodyMedium;
  final TextStyle labelSmall;
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
      titleMedium: tabular(textTheme.titleMedium),
      headlineSmall: tabular(textTheme.headlineSmall),
    );
  }

  @override
  AppNumericTextStyles copyWith({
    TextStyle? bodySmall,
    TextStyle? bodyMedium,
    TextStyle? labelSmall,
    TextStyle? titleMedium,
    TextStyle? headlineSmall,
  }) {
    return AppNumericTextStyles(
      bodySmall: bodySmall ?? this.bodySmall,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      labelSmall: labelSmall ?? this.labelSmall,
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
      titleMedium: TextStyle.lerp(titleMedium, other.titleMedium, t)!,
      headlineSmall: TextStyle.lerp(headlineSmall, other.headlineSmall, t)!,
    );
  }
}

/// 명시적 [ColorScheme].
///
/// 기존 `ColorScheme.fromSeed(0xFF3D5AFE)`의 인디고 색조는 유지하되 채도를 낮춰
/// (`#3D5AFE` → `#414CB8`) 사진 옆에서 UI가 먼저 눈에 들어오지 않게 한다.
abstract final class AppColorSchemes {
  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF414CB8),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDDE1FF),
    onPrimaryContainer: Color(0xFF050B49),
    secondary: Color(0xFF5A5D72),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDFE1F9),
    onSecondaryContainer: Color(0xFF2C2F43),
    tertiary: Color(0xFF74566E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8EE),
    onTertiaryContainer: Color(0xFF43263E),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF601410),
    surface: Color(0xFFFDFBFF),
    onSurface: Color(0xFF1B1B21),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF8F5FC),
    surfaceContainer: Color(0xFFF2F0F7),
    surfaceContainerHigh: Color(0xFFECEAF2),
    surfaceContainerHighest: Color(0xFFE4E2E9),
    onSurfaceVariant: Color(0xFF5F5D67),
    outline: Color(0xFF78767F),
    outlineVariant: Color(0xFFC7C5D0),
    inverseSurface: Color(0xFF303038),
    onInverseSurface: Color(0xFFF2F0F7),
    inversePrimary: Color(0xFFB6BEFF),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB6BEFF),
    onPrimary: Color(0xFF14206B),
    primaryContainer: Color(0xFF2A3690),
    onPrimaryContainer: Color(0xFFDDE1FF),
    secondary: Color(0xFFC3C5DD),
    onSecondary: Color(0xFF2C2F43),
    secondaryContainer: Color(0xFF43465A),
    onSecondaryContainer: Color(0xFFDFE1F9),
    tertiary: Color(0xFFE2BAD6),
    onTertiary: Color(0xFF43263E),
    tertiaryContainer: Color(0xFF5C3C55),
    onTertiaryContainer: Color(0xFFFFD8EE),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF121318),
    onSurface: Color(0xFFE4E2E9),
    surfaceContainerLowest: Color(0xFF0D0E12),
    surfaceContainerLow: Color(0xFF1B1B21),
    surfaceContainer: Color(0xFF1F1F26),
    surfaceContainerHigh: Color(0xFF2A2A31),
    surfaceContainerHighest: Color(0xFF303038),
    onSurfaceVariant: Color(0xFFC7C5D0),
    outline: Color(0xFF918F9A),
    outlineVariant: Color(0xFF47464F),
    inverseSurface: Color(0xFFE4E2E9),
    onInverseSurface: Color(0xFF303038),
    inversePrimary: Color(0xFF414CB8),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
  );
}

/// 호출부에서 `Theme.of(context).extension<...>()!`를 반복하지 않게 한다.
extension AppThemeAccess on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;

  /// success / warning.
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
