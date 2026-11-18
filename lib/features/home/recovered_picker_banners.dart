import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/korean_text.dart';
import '../../core/services/app_image_picker.dart';
import '../members/member_providers.dart';
import '../members/ui.dart';
import '../videos/video_providers.dart';

/// Android에서 사진·동영상 선택 중 앱이 종료돼 복구된 결과 안내.
///
/// 앱을 다시 열면 홈이 첫 화면이므로 홈 한 곳에서만 보인다. 결과를 어느 회원
/// 레슨에도 자동으로 붙이지 않고, 확인할 화면으로 가는 길만 연다.
class RecoveredPickerBanners extends ConsumerWidget {
  const RecoveredPickerBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovered = ref.watch(appImagePickerCoordinatorProvider);
    if (recovered == null) return const SizedBox.shrink();
    return switch (recovered.context.operation) {
      ImagePickerOperation.galleryImport => mark(
        'members.recoveredPhotos.banner',
        MaterialBanner(
          content: Text(
            keepPhrasesWhole('중단된 사진 선택을 복구했어요. 확인 후 회원에게 연결할 수 있어요.'),
          ),
          actions: [
            TextButton(
              onPressed: () => context.push('/import'),
              child: const Text('사진 확인'),
            ),
          ],
        ),
      ),
      ImagePickerOperation.lessonVideo => _video(context, ref, recovered),
      ImagePickerOperation.photoReplacement => const SizedBox.shrink(),
    };
  }

  Widget _video(
    BuildContext context,
    WidgetRef ref,
    RecoveredImagePickerSelection recovered,
  ) {
    final c = recovered.context;
    final member = ref
        .watch(membersProvider)
        .valueOrNull
        ?.where((m) => m.id == c.memberId)
        .firstOrNull;
    return mark(
      'members.recoveredVideo.banner',
      MaterialBanner(
        content: Text(
          keepPhrasesWhole(
            member == null
                ? '중단된 동영상 선택을 복구했어요. 선택한 회원을 찾을 수 없어요.'
                : '중단된 동영상 선택을 복구했어요. ${member.name} 회원의 레슨에 붙일 수 있어요.',
          ),
        ),
        actions: [
          mark(
            'members.recoveredVideo.discard.button',
            TextButton(
              onPressed: () async {
                final cleaner = ref.read(pickerCopyCleanerProvider);
                try {
                  await ref
                      .read(appImagePickerCoordinatorProvider.notifier)
                      .acknowledgeRecovered(c);
                } catch (_) {
                  return;
                }
                for (final f in recovered.files) {
                  unawaited(cleaner(f.path));
                }
              },
              child: const Text('버리기'),
            ),
          ),
          if (member != null)
            mark(
              'members.recoveredVideo.open.button',
              TextButton(
                onPressed: () => context.push(
                  c.recordId == null
                      ? '/members/${member.id}/lessons/new'
                      : '/members/${member.id}/lessons/${c.recordId}/edit',
                ),
                child: const Text('레슨에서 확인'),
              ),
            ),
        ],
      ),
    );
  }
}
