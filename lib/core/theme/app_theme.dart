import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 앱 테마. Material 3 기반.
///
/// 색상은 seed 자동 생성 대신 [AppColorSchemes]의 명시적 팔레트를 쓴다. M3 롤에
/// 없는 상태 색과 사진 서페이스, 수치 타이포는 [ThemeExtension]으로 더한다.
/// 호출부는 `context.colors` / `context.semanticColors` / `context.photoColors` /
/// `context.numericTexts`로 읽는다([AppThemeAccess]).
class AppTheme {
  AppTheme._();

  static ThemeData get light =>
      _build(AppColorSchemes.light, AppSemanticColors.light);

  static ThemeData get dark =>
      _build(AppColorSchemes.dark, AppSemanticColors.dark);

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    final texts = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.5),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.lgAll);
    return base.copyWith(
      textTheme: texts,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: texts.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 52),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      // 입력 테두리를 여기서 한 번 정의해 호출부에서 border를 반복하지 않는다.
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: AppRadius.smAll),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.all(AppSpacing.sp3),
      ),

      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),

      dialogTheme: base.dialogTheme.copyWith(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),

      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      extensions: <ThemeExtension<dynamic>>[
        semantic,
        const AppPhotoColors(),
        AppNumericTextStyles.from(texts),
      ],
    );
  }
}
