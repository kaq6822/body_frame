import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../records/providers/records_providers.dart';
import 'ui.dart';

class MemberCompareScreen extends ConsumerStatefulWidget {
  final String memberId;
  const MemberCompareScreen({super.key, required this.memberId});
  @override
  ConsumerState<MemberCompareScreen> createState() => _MemberCompareState();
}

class _MemberCompareState extends ConsumerState<MemberCompareScreen> {
  String? before, after;
  BodyDirection direction = BodyDirection.front;
  @override
  Widget build(BuildContext context) => mark(
    'screen.members.compare',
    Scaffold(
      appBar: AppBar(title: const Text('비교 기록 선택')),
      body: ref
          .watch(timelineProvider)
          .when(
            loading: () => busy('members.compare.loading'),
            error: (_, _) => failure(
              'members.compare.error',
              '비교할 기록을 불러오지 못했어요.',
              () => ref.invalidate(timelineProvider),
            ),
            data: (items) {
              final entries =
                  <
                    ({PhotoRecord record, String phase, List<BodyPhoto> photos})
                  >[];
              for (final item in items.where(
                (x) => x.record.memberId == widget.memberId,
              )) {
                for (final phase in phases.keys) {
                  final photos = item.photos
                      .where((p) => p.phase == phase)
                      .toList();
                  if (photos.isNotEmpty) {
                    entries.add((
                      record: item.record,
                      phase: phase,
                      photos: photos,
                    ));
                  }
                }
              }
              String key(
                ({PhotoRecord record, String phase, List<BodyPhoto> photos}) e,
              ) => '${e.record.id}:${e.phase}';
              final a = entries.where((e) => key(e) == before).firstOrNull;
              final b = entries.where((e) => key(e) == after).firstOrNull;
              final ap = a?.photos
                  .where((p) => p.direction == direction)
                  .firstOrNull;
              final bp = b?.photos
                  .where((p) => p.direction == direction)
                  .firstOrNull;
              final valid = ap != null && bp != null && ap.id != bp.id;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '같은 회원의 사진 기록 두 개를 선택해주세요.\n같은 레슨의 수업 전·후도 비교할 수 있어요.',
                  ),
                  const SizedBox(height: 16),
                  if (entries.length < 2)
                    section(
                      '비교할 사진 기록이 부족해요',
                      const Text(
                        '사진 기록을 두 개 이상 남긴 뒤 비교해주세요. 일지는 계속 작성할 수 있어요.',
                      ),
                    ),
                  mark(
                    'members.compare.direction',
                    DropdownButton<BodyDirection>(
                      value: direction,
                      isExpanded: true,
                      items: [
                        for (final d in BodyDirection.values.take(4))
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (v) => setState(() => direction = v!),
                    ),
                  ),
                  for (final e in entries)
                    panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${lessonDate(e.record.shotAt)} · ${phases[e.phase]}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            e.photos
                                .map((p) => p.direction.label)
                                .toSet()
                                .join(' · '),
                          ),
                          Wrap(
                            spacing: 12,
                            children: [
                              mark(
                                'members.compare.${key(e)}.before',
                                ChoiceChip(
                                  label: const Text('A 이전'),
                                  selected: before == key(e),
                                  onSelected: (_) =>
                                      setState(() => before = key(e)),
                                ),
                              ),
                              mark(
                                'members.compare.${key(e)}.after',
                                ChoiceChip(
                                  label: const Text('B 이후'),
                                  selected: after == key(e),
                                  onSelected: (_) =>
                                      setState(() => after = key(e)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (a != null && b != null && !valid)
                    section(
                      '이 방향으로 비교할 수 없어요',
                      Text(
                        before == after
                            ? '서로 다른 사진 기록을 선택해주세요.'
                            : '${direction.label} 사진이 양쪽 기록에 모두 있어야 해요. 다른 방향을 선택해주세요.',
                      ),
                    ),
                  action(
                    'members.compare.open.button',
                    '비교하기',
                    !valid
                        ? null
                        : () => context.pushNamed(
                            AppRoutes.compareView,
                            queryParameters: {
                              AppParams.beforePhotoId: ap.id,
                              AppParams.afterPhotoId: bp.id,
                            },
                          ),
                    icon: Icons.compare,
                  ),
                ],
              );
            },
          ),
    ),
  );
}
