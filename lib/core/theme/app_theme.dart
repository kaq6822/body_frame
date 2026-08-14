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

    return base.copyWith(
      appBarTheme: const AppBarTheme(centerTitle: true),

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
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
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
        AppNumericTextStyles.from(base.textTheme),
      ],
    );
  }
}
