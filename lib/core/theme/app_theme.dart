import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 앱 테마. Material 3 기반.
///
/// 색상은 seed 자동 생성 대신 [AppColorSchemes]의 명시적 팔레트를 쓴다. M3 롤에
/// 없는 상태 색과 사진 서페이스, 수치 타이포는 [ThemeExtension]으로 더한다.
/// 호출부는 `context.colors` / `context.semanticColors` / `context.photoColors` /
/// `context.numericTexts`로 읽는다([AppThemeAccess]).
///
/// 면은 그림자 없이 1px 테두리로 구분한다. 카드·입력 r8, 버튼 r6, 다이얼로그·
/// 바텀시트 r12, 상태 칩만 완전 둥근 모양이다.
class AppTheme {
  AppTheme._();

  /// 번들 글꼴 family 이름(pubspec.yaml).
  static const fontFamily = 'Pretendard';

  static ThemeData get light =>
      _build(AppColorSchemes.light, AppSemanticColors.light);

  static ThemeData get dark =>
      _build(AppColorSchemes.dark, AppSemanticColors.dark);

  /// DESIGN.md 타입 스케일을 M3 [TextTheme] 롤에 대응시킨다.
  ///
  /// headline-xl 32 → headlineLarge, headline-lg 24 → headlineMedium,
  /// headline-sm 18 → titleLarge(앱바 제목은 700으로 올린다), 섹션·목록 제목 16 →
  /// titleMedium, body-lg/md/sm 16/14/13 → bodyLarge/Medium/Small,
  /// label-lg/md/sm 14/12/11 → labelLarge/Medium/Small.
  static TextTheme _textTheme(TextTheme base) {
    TextStyle? scale(
      TextStyle? style,
      double size,
      FontWeight weight,
      double lineHeight,
      double trackingEm,
    ) => style?.copyWith(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      height: lineHeight / size,
      letterSpacing: size * trackingEm,
    );

    return base.copyWith(
      headlineLarge: scale(base.headlineLarge, 32, FontWeight.w700, 40, -0.02),
      headlineMedium: scale(
        base.headlineMedium,
        24,
        FontWeight.w700,
        32,
        -0.015,
      ),
      headlineSmall: scale(base.headlineSmall, 20, FontWeight.w700, 28, -0.01),
      titleLarge: scale(base.titleLarge, 18, FontWeight.w600, 26, -0.01),
      titleMedium: scale(base.titleMedium, 16, FontWeight.w600, 24, -0.005),
      titleSmall: scale(base.titleSmall, 14, FontWeight.w600, 20, 0),
      bodyLarge: scale(base.bodyLarge, 16, FontWeight.w500, 24, -0.005),
      bodyMedium: scale(base.bodyMedium, 14, FontWeight.w400, 20, 0),
      bodySmall: scale(base.bodySmall, 13, FontWeight.w400, 18, 0),
      labelLarge: scale(base.labelLarge, 14, FontWeight.w600, 20, 0.01),
      labelMedium: scale(base.labelMedium, 12, FontWeight.w600, 16, 0.02),
      labelSmall: scale(base.labelSmall, 11, FontWeight.w600, 14, 0.04),
    );
  }

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final isLight = scheme.brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );
    final texts = _textTheme(base.textTheme);

    // 카드·다이얼로그·시트처럼 바탕 위에 놓이는 면. 라이트는 순백, 다크는 slate 800.
    final raised = scheme.surfaceContainerLowest;
    final hairline = BorderSide(color: scheme.outlineVariant);
    final strongLine = BorderSide(color: scheme.outline);
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.smAll);
    const minButton = Size(
      AppSpacing.minTouchTarget,
      AppSpacing.minTouchTarget,
    );
    final pressed = AppColorSchemes.pressedPrimary(scheme.brightness);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: texts,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: texts.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: minButton,
              shape: buttonShape,
              textStyle: texts.labelLarge,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return scheme.onSurface.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.pressed)) return pressed;
                return null;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minButton,
          shape: buttonShape,
          side: strongLine,
          foregroundColor: scheme.onSurface,
          backgroundColor: raised,
          textStyle: texts.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minButton,
          shape: buttonShape,
          textStyle: texts.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: minButton,
          shape: buttonShape,
          elevation: 0,
          backgroundColor: raised,
          side: hairline,
          textStyle: texts.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minButton),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      // 입력 테두리를 여기서 한 번 정의해 호출부에서 border를 반복하지 않는다.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        border: inputBorder(scheme.outline),
        enabledBorder: inputBorder(scheme.outline),
        disabledBorder: inputBorder(scheme.outlineVariant),
        focusedBorder: inputBorder(scheme.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
        hintStyle: texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp3,
          vertical: AppSpacing.sp3,
        ),
      ),

      cardTheme: base.cardTheme.copyWith(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: hairline,
        ),
      ),

      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: texts.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: texts.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: texts.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: strongLine,
        backgroundColor: raised,
        selectedColor: scheme.primaryContainer,
        labelStyle: texts.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: texts.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        checkmarkColor: scheme.primary,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minButton),
          shape: const WidgetStatePropertyAll(buttonShape),
          side: WidgetStatePropertyAll(strongLine),
          textStyle: WidgetStatePropertyAll(texts.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? scheme.primary : raised,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant;
          }),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => texts.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        labelStyle: texts.labelLarge,
        unselectedLabelStyle: texts.labelLarge,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : (isLight ? Colors.white : scheme.onSurfaceVariant),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),

      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: texts.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: texts.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: texts.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
      ),

      extensions: <ThemeExtension<dynamic>>[
        semantic,
        const AppPhotoColors(),
        AppNumericTextStyles.from(texts),
      ],
    );
  }
}
