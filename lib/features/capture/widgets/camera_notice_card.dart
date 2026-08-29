import 'package:flutter/material.dart';

import '../../../core/korean_text.dart';
import '../../../core/theme/app_tokens.dart';

/// 안내의 성격. 배지 아이콘과 강조색을 결정한다.
enum CameraNoticeTone {
  /// 초기화 진행 중. 사용자가 할 일은 없다.
  busy,

  /// 사용자가 조치하면 풀리는 상태(권한 미허용 등).
  actionNeeded,

  /// 앱이 손쓸 수 없는 실패.
  failure,
}

/// 카메라 미리보기 자리에 띄우는 안내 카드.
///
/// 홈이 카메라인 앱이라 미리보기가 없으면 첫 화면이 검은 판이 된다. 이 카드가
/// 그 자리에서 "지금 무슨 상태이고 무엇을 하면 되는지"를 대신 말한다.
///
/// 배경([AppPhotoColors.backdrop])이 거의 검정이므로 카드를 밝게 깔아 대비를
/// 확보하고, 배지 → 제목 → 설명 → 경로 → 액션 순서로 위계를 준다.
class CameraNoticeCard extends StatelessWidget {
  /// `screen.<x>.status` 형태의 상태 식별자.
  ///
  /// 재시도 버튼 키는 여기서 파생한다(`<statusId>.retry.button`). 스크린리더는
  /// 이 노드의 value로 상태를 읽는다.
  final String statusId;

  final CameraNoticeTone tone;
  final String title;
  final String? description;

  /// 기기 설정에서 따라갈 경로. **단계 단위로 나눠** 넘긴다.
  ///
  /// [onOpenSettings]로 곧바로 갈 수 있으므로 이 경로는 보조 안내다. 버튼이 막힌
  /// 기기나 사용자가 직접 확인하고 싶을 때를 위해 카드 맨 아래에 작게 둔다.
  final List<String> settingsPath;

  /// [settingsPath] 위에 붙는 한 줄. 경로가 있을 때만 쓰인다.
  final String? settingsPathHint;

  /// 시스템 설정 화면 열기. 있으면 이것이 주 동작이 된다.
  final VoidCallback? onOpenSettings;
  final String openSettingsLabel;

  final String retryLabel;
  final VoidCallback? onRetry;

  /// 액션 아래에 놓이는 보조 동선(기록 보기 등).
  final Widget? secondaryAction;

  const CameraNoticeCard({
    super.key,
    required this.statusId,
    required this.tone,
    required this.title,
    this.description,
    this.settingsPath = const [],
    this.settingsPathHint,
    this.onOpenSettings,
    this.openSettingsLabel = '설정 열기',
    this.retryLabel = '다시 시도',
    this.onRetry,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final busy = tone == CameraNoticeTone.busy;

    return Semantics(
      identifier: statusId,
      value: busy ? 'busy' : 'failure',
      liveRegion: !busy,
      container: true,
      // 이 노드는 상태(식별자와 value)만 알린다. 붙이지 않으면 제목·설명·경로가
      // 이 노드로 합쳐지면서 첫 문장만 남고, 정작 무엇을 하라는 안내와 설정 경로가
      // 스크린리더에 전달되지 않는다.
      explicitChildNodes: true,
      child: Container(
        key: ValueKey(statusId),
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.all(AppSpacing.sp5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sp5,
          vertical: AppSpacing.sp6,
        ),
        decoration: BoxDecoration(
          color: _cardColor(colors),
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            // 카드가 뷰파인더 위에 떠 있다는 것을 알린다. 검은 배경에서는
            // 테두리만으로 경계가 잘 읽히지 않는다.
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBadge(context),
            const SizedBox(height: AppSpacing.sp4),
            // 표시 문자열만 어절을 묶고, 읽어 줄 문장은 원문으로 남긴다.
            Text(
              keepPhrasesWhole(title),
              semanticsLabel: title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description case final text?) ...[
              const SizedBox(height: AppSpacing.sp2),
              Text(
                keepPhrasesWhole(text),
                semanticsLabel: text,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            // 액션이 먼저다. 설정으로 바로 갈 수 있는데 경로부터 읽히면 사용자는
            // 하지 않아도 될 일을 하게 된다. 경로는 카드 맨 아래 보조로 내린다.
            if (onOpenSettings case final open?) ...[
              const SizedBox(height: AppSpacing.sp5),
              Semantics(
                identifier: '$statusId.settings.button',
                button: true,
                label: openSettingsLabel,
                child: FilledButton(
                  key: ValueKey('$statusId.settings.button'),
                  onPressed: open,
                  child: Text(openSettingsLabel),
                ),
              ),
            ],
            if (onRetry case final retry?) ...[
              SizedBox(
                height: onOpenSettings == null ? AppSpacing.sp5 : AppSpacing.sp1,
              ),
              // 주 동작이 이미 있으면 재시도는 한 단계 낮춘다. 버튼 두 개가 같은
              // 무게로 놓이면 무엇을 눌러야 할지 고민하게 된다.
              Semantics(
                identifier: '$statusId.retry.button',
                button: true,
                label: retryLabel,
                child: onOpenSettings == null
                    ? FilledButton(
                        key: ValueKey('$statusId.retry.button'),
                        onPressed: retry,
                        child: Text(retryLabel),
                      )
                    : TextButton(
                        key: ValueKey('$statusId.retry.button'),
                        onPressed: retry,
                        child: Text(retryLabel),
                      ),
              ),
            ],
            if (secondaryAction case final action?) ...[
              const SizedBox(height: AppSpacing.sp1),
              action,
            ],
            if (settingsPath.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sp4),
              _buildSettingsPath(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 카드 배경.
  ///
  /// 다크 스킴의 `surface`(0xFF121318)는 미리보기 배경
  /// ([AppPhotoColors.backdrop], 0xFF101114)과 거의 같아 카드가 배경에 녹는다.
  /// 그래서 라이트는 가장 흰 단계를, 다크는 한 단계 띄운 컨테이너 색을 쓴다.
  Color _cardColor(ColorScheme colors) =>
      colors.brightness == Brightness.dark
      ? colors.surfaceContainerHigh
      : colors.surfaceContainerLowest;

  Widget _buildBadge(BuildContext context) {
    if (tone == CameraNoticeTone.busy) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    // 권한은 조치하면 풀리는 상태라 경고 톤을, 그 밖의 실패는 오류 톤을 쓴다.
    final (Color background, Color foreground, IconData icon) =
        switch (tone) {
          CameraNoticeTone.actionNeeded => (
            context.semanticColors.warningContainer,
            context.semanticColors.onWarningContainer,
            Icons.no_photography_outlined,
          ),
          _ => (
            context.colors.errorContainer,
            context.colors.onErrorContainer,
            Icons.videocam_off_outlined,
          ),
        };

    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 28, color: foreground),
      ),
    );
  }

  /// 설정 경로를 한 줄 텍스트로 만든다. 줄바꿈은 **단계 사이에서만** 일어난다.
  ///
  /// 세 가지를 동시에 만족해야 한다.
  ///
  /// 1. 단계 이름은 통째로 남아야 한다("애플리 / 케이션"이 되면 안 된다).
  ///    → 단계 안쪽은 [keepPhrasesWhole]로 묶는다.
  /// 2. 줄이 넘어갈 때 다음 줄이 구분자로 시작하면 경로가 어디서 이어지는지
  ///    눈으로 따라가기 어렵다. → 단계와 뒤따르는 `›`를 줄바꿈 없는 공백으로
  ///    붙여 `설정 ›`가 한 덩어리로 움직이게 한다. 줄은 `›` 다음의 보통 공백에서만
  ///    넘어가므로 항상 "…권한 ›" / "카메라" 모양이 된다.
  /// 3. 좁은 폭에서도 넘치지 않아야 한다. → 위젯을 나열하는 대신 단일 [Text]로
  ///    두어 줄바꿈을 텍스트 레이아웃에 맡긴다. 아이콘과 [Row]로 조립하면 폭이
  ///    모자랄 때 오버플로가 난다.
  Widget _buildSettingsPath(BuildContext context) {
    final colors = context.colors;

    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp3,
        vertical: AppSpacing.sp3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (settingsPathHint case final hint?) ...[
            Text(
              keepPhrasesWhole(hint),
              semanticsLabel: hint,
              style: textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
            const SizedBox(height: AppSpacing.sp1),
          ],
          Text(
            joinBreadcrumb(settingsPath),
            // 읽어 줄 때는 화살표 대신 사람이 말하는 순서로 들려준다.
            semanticsLabel: settingsPath.join(', '),
            // 여러 줄이 될 때 가운데 정렬은 둘째 줄이 허공에 뜬 것처럼 보인다.
            // 경로는 순서를 따라 읽는 목록이라 시작을 왼쪽에 맞춘다.
            textAlign: TextAlign.start,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
