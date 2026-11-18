import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 확인 다이얼로그를 띄우고 사용자가 확인을 눌렀는지 돌려준다.
///
/// 바깥을 눌러 닫거나 뒤로가기로 닫으면 `false`다. 삭제처럼 되돌릴 수 없는 동작은
/// [destructive]를 켜고 [summary]에 함께 사라지는 범위를 적는다.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  String? body,
  String confirmLabel = '확인',
  String cancelLabel = '취소',
  IconData? icon,
  bool destructive = false,
  bool preferCancel = false,
  List<String> summary = const [],
  String? warning,
  String dialogKey = AppConfirmDialog.defaultDialogKey,
  String cancelKey = AppConfirmDialog.defaultCancelKey,
  String confirmKey = AppConfirmDialog.defaultConfirmKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AppConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      destructive: destructive,
      preferCancel: preferCancel,
      summary: summary,
      warning: warning,
      dialogKey: dialogKey,
      cancelKey: cancelKey,
      confirmKey: confirmKey,
    ),
  );
  return result ?? false;
}

/// 아이콘 배지 + 질문형 제목 + 본문 + (선택) 범위 요약 + 취소/확인.
///
/// 취소는 [Navigator.pop]에 `false`, 확인은 `true`를 넘긴다. 키와 Semantics
/// identifier는 같은 문자열을 쓴다.
class AppConfirmDialog extends StatelessWidget {
  static const defaultDialogKey = 'common.confirm.dialog';
  static const defaultCancelKey = 'common.confirm.cancel.button';
  static const defaultConfirmKey = 'common.confirm.accept.button';

  final String title;
  final String? body;
  final String confirmLabel;
  final String cancelLabel;

  /// null이면 [destructive]일 때 휴지통, 아니면 물음표 아이콘.
  final IconData? icon;
  final bool destructive;

  /// 취소 쪽이 권장 동작일 때 켠다(예: 작성 중 나가기의 "계속 작성").
  /// 취소를 주요 버튼으로 위에, 확인을 외곽선 버튼으로 아래에 쌓고 배지는 경고
  /// 톤이 된다.
  final bool preferCancel;

  /// 함께 영향을 받는 범위. 예: "사진 4장, 메모 1개가 함께 삭제돼요".
  final List<String> summary;

  /// 본문 아래 강조 문구. 예: "삭제 후 되돌릴 수 없어요."
  final String? warning;

  final String dialogKey;
  final String cancelKey;
  final String confirmKey;

  const AppConfirmDialog({
    super.key,
    required this.title,
    this.body,
    this.confirmLabel = '확인',
    this.cancelLabel = '취소',
    this.icon,
    this.destructive = false,
    this.preferCancel = false,
    this.summary = const [],
    this.warning,
    this.dialogKey = defaultDialogKey,
    this.cancelKey = defaultCancelKey,
    this.confirmKey = defaultConfirmKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final semantic = context.semanticColors;
    final (Color accent, Color badge, IconData defaultIcon) = preferCancel
        ? (
            semantic.warning,
            semantic.warningContainer,
            Icons.warning_amber_rounded,
          )
        : destructive
        ? (colors.error, colors.errorContainer, Icons.delete_outline)
        : (colors.primary, colors.primaryContainer, Icons.help_outline);
    final stacked =
        preferCancel || MediaQuery.textScalerOf(context).scale(1) > 1.3;

    void cancelTap() => Navigator.of(context).pop(false);
    void acceptTap() => Navigator.of(context).pop(true);
    final cancelText = Text(cancelLabel, textAlign: TextAlign.center);
    final acceptText = Text(confirmLabel, textAlign: TextAlign.center);

    final cancel = Semantics(
      identifier: cancelKey,
      child: preferCancel
          ? FilledButton(
              key: ValueKey(cancelKey),
              onPressed: cancelTap,
              child: cancelText,
            )
          : OutlinedButton(
              key: ValueKey(cancelKey),
              onPressed: cancelTap,
              child: cancelText,
            ),
    );
    final accept = Semantics(
      identifier: confirmKey,
      child: preferCancel
          ? OutlinedButton(
              key: ValueKey(confirmKey),
              style: destructive
                  ? OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.errorContainer),
                    )
                  : null,
              onPressed: acceptTap,
              child: acceptText,
            )
          : FilledButton(
              key: ValueKey(confirmKey),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    )
                  : null,
              onPressed: acceptTap,
              child: acceptText,
            ),
    );
    // 권장 동작을 위에 둔다.
    final (Widget first, Widget second) = preferCancel
        ? (cancel, accept)
        : (accept, cancel);

    return Semantics(
      identifier: dialogKey,
      container: true,
      child: Dialog(
        key: ValueKey(dialogKey),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp6,
          vertical: AppSpacing.sp6,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: badge,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon ?? defaultIcon, color: accent),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sp4),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: texts.titleLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: AppSpacing.sp2),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: texts.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sp4),
                Container(
                  key: ValueKey('$dialogKey.summary'),
                  padding: const EdgeInsets.all(AppSpacing.sp3),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in summary)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sp1 / 2,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.remove,
                                  size: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sp2),
                              Expanded(
                                child: Text(
                                  line,
                                  style: texts.bodySmall?.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (warning != null) ...[
                const SizedBox(height: AppSpacing.sp3),
                Text(
                  warning!,
                  textAlign: TextAlign.center,
                  style: texts.bodyMedium?.copyWith(
                    color: destructive ? colors.error : colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sp6),
              if (stacked) ...[
                first,
                const SizedBox(height: AppSpacing.sp2),
                second,
              ] else
                Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: AppSpacing.sp3),
                    Expanded(child: accept),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
