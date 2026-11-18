import 'package:flutter/material.dart';

import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/theme/app_tokens.dart';
import 'package:bodymark/core/widgets/bottom_action_bar.dart';
import '../members/ui.dart';
import 'providers/capture_session_provider.dart';
import 'utils/capture_guides.dart';

/// 촬영 가이드(Stitch 21). 번호 단계 + 표준 촬영 순서 + 하단 고정 복귀 버튼.
class CaptureGuideScreen extends StatelessWidget {
  const CaptureGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => mark(
    'screen.capture.guide',
    Scaffold(
      appBar: AppBar(title: const Text('촬영 가이드')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sp4),
        children: [
          for (var i = 0; i < captureGuideSteps.length; i++)
            _GuideStepCard(
              index: i + 1,
              title: captureGuideSteps[i].$1,
              body: captureGuideSteps[i].$2,
            ),
          Container(
            key: const ValueKey('capture.guide.note'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sp4),
            padding: const EdgeInsets.all(AppSpacing.sp4),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Text(
              '이전 자세를 억지로 따라 하지 마세요. 모든 방향이 필수는 아니에요.',
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const _StandardOrderCard(),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        identifier: 'capture.guide.actions',
        primary: Semantics(
          identifier: 'capture.guide.back.button',
          button: true,
          child: FilledButton.icon(
            key: const ValueKey('capture.guide.back.button'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('촬영으로 돌아가기'),
          ),
        ),
      ),
    ),
  );
}

class _GuideStepCard extends StatelessWidget {
  final int index;
  final String title;
  final String body;

  const _GuideStepCard({
    required this.index,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final id = 'capture.guide.step.$index';
    return Semantics(
      identifier: id,
      container: true,
      label: '$index단계',
      child: Card(
        key: ValueKey(id),
        margin: const EdgeInsets.only(bottom: AppSpacing.sp3),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primaryContainer,
                  ),
                  child: Text(
                    '$index',
                    style: context.numericTexts.labelLarge.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.texts.titleMedium),
                    const SizedBox(height: AppSpacing.sp1),
                    Text(
                      body,
                      style: context.texts.bodyMedium?.copyWith(
                        height: 1.55,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandardOrderCard extends StatelessWidget {
  const _StandardOrderCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labels = [for (final d in kSessionDirections) d.label];
    return Semantics(
      identifier: 'capture.guide.order',
      container: true,
      label: '표준 촬영 순서: ${labels.join(', ')}',
      excludeSemantics: true,
      child: Card(
        key: const ValueKey('capture.guide.order'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '표준 촬영 순서',
                style: context.texts.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sp3),
              Wrap(
                spacing: AppSpacing.sp1,
                runSpacing: AppSpacing.sp2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < kSessionDirections.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    _OrderChip(
                      label: kSessionDirections[i].label,
                      first: kSessionDirections[i] == BodyDirection.front,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  final String label;
  final bool first;

  const _OrderChip({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sp3,
        vertical: AppSpacing.sp2,
      ),
      decoration: BoxDecoration(
        color: first ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: context.texts.labelLarge?.copyWith(
          color: first ? colors.onPrimaryContainer : colors.onSurface,
        ),
      ),
    );
  }
}
