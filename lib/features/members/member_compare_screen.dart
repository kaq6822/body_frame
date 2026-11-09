import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bottom_action_bar.dart';
import '../../core/widgets/direction_stepper.dart';
import '../../core/widgets/status_pill.dart';
import '../compare/compare_logic.dart';
import '../records/providers/records_providers.dart';
import 'member_providers.dart';
import 'ui.dart';

/// 회원의 사진 기록 하나(레슨 기록 × 수업 단계).
///
/// 같은 레슨의 수업 전·후를 비교할 수 있게 단계별로 나눈다.
typedef _Entry = ({PhotoRecord record, String phase, List<BodyPhoto> photos});

String _entryKey(_Entry e) => '${e.record.id}:${e.phase}';

/// 같은 시각이면 수업 전 → 정기 → 수업 후 순서가 이르다.
const _phaseOrder = {'before': 0, 'regular': 1, 'after': 2};

int _compareEntries(_Entry a, _Entry b) {
  final byTime = a.record.shotAt.compareTo(b.record.shotAt);
  if (byTime != 0) return byTime;
  return (_phaseOrder[a.phase] ?? 1).compareTo(_phaseOrder[b.phase] ?? 1);
}

/// 비교 기록 선택 화면(Stitch 28–30).
///
/// 두 기록을 탭으로 고르면 고른 순서와 관계없이 이른 기록을 이전(A), 늦은
/// 기록을 이후(B)로 배치한다. 두 기록에 함께 있는 방향만 고를 수 있다.
class MemberCompareScreen extends ConsumerStatefulWidget {
  final String memberId;
  const MemberCompareScreen({super.key, required this.memberId});
  @override
  ConsumerState<MemberCompareScreen> createState() => _MemberCompareState();
}

class _MemberCompareState extends ConsumerState<MemberCompareScreen> {
  /// 고른 기록 키(최대 2개, 고른 순서).
  final List<String> _picked = [];
  BodyDirection? _direction;

  void _toggle(String key) {
    setState(() {
      if (_picked.remove(key)) return;
      // 이미 두 개면 나중에 고른 것을 바꾼다. 먼저 고른 기준은 유지한다.
      if (_picked.length == 2) _picked.removeLast();
      _picked.add(key);
    });
  }

  String? _memberName() => ref
      .watch(membersProvider)
      .valueOrNull
      ?.where((m) => m.id == widget.memberId)
      .firstOrNull
      ?.name;

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final entries = <_Entry>[];
    for (final item in timeline.valueOrNull ?? const <RecordWithPhotos>[]) {
      if (item.record.memberId != widget.memberId) continue;
      for (final phase in phases.keys) {
        final photos = item.photos.where((p) => p.phase == phase).toList();
        if (photos.isNotEmpty) {
          entries.add((record: item.record, phase: phase, photos: photos));
        }
      }
    }
    // 사라진 기록(삭제 등)은 선택에서 뺀다.
    if (timeline.hasValue) {
      final keys = entries.map(_entryKey).toSet();
      _picked.removeWhere((k) => !keys.contains(k));
    }

    final name = _memberName();
    final notEnough = timeline.hasValue && entries.length < 2;

    final Widget body;
    Widget? bottom;
    if (timeline.isLoading && !timeline.hasValue) {
      body = busy('members.compare.loading');
    } else if (timeline.hasError && !timeline.hasValue) {
      body = failure(
        'members.compare.error',
        '비교할 기록을 불러오지 못했어요.',
        () => ref.invalidate(timelineProvider),
      );
    } else if (notEnough) {
      body = _NotEnoughRecords(count: entries.length);
      bottom = BottomActionBar(
        identifier: 'members.compare.notEnough.actions',
        primary: mark(
          'members.compare.add.button',
          FilledButton.icon(
            onPressed: () =>
                context.push('/members/${widget.memberId}/lessons/new'),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('사진 기록 추가하기'),
          ),
        ),
        secondary: mark(
          'members.compare.back.button',
          OutlinedButton(
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go('/members/${widget.memberId}'),
            child: const Text('회원으로'),
          ),
        ),
      );
    } else {
      final selection = _resolveSelection(entries);
      body = _buildList(entries, selection);
      bottom = _buildActions(selection);
    }

    return mark(
      'screen.members.compare',
      Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('비교 기록 선택'),
              if (name != null)
                Text(
                  '$name 회원',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          actions: [
            if (!notEnough && timeline.hasValue)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sp4),
                child: Center(
                  child: StatusPill(
                    identifier: 'members.compare.selected.count',
                    label: '선택됨 ${_picked.length}/2',
                    tone: _picked.length == 2
                        ? StatusPillTone.primary
                        : StatusPillTone.neutral,
                  ),
                ),
              ),
          ],
        ),
        body: body,
        bottomNavigationBar: bottom,
      ),
    );
  }

  _Selection _resolveSelection(List<_Entry> entries) {
    final picked = [
      for (final k in _picked) entries.firstWhere((e) => _entryKey(e) == k),
    ]..sort(_compareEntries);
    if (picked.length < 2) {
      return _Selection(
        a: picked.firstOrNull,
        b: null,
        directions: const [],
        direction: null,
      );
    }
    final a = picked[0];
    final b = picked[1];
    final directions = commonDirections(a.photos, b.photos);
    final direction = directions.contains(_direction)
        ? _direction
        : directions.firstOrNull;
    return _Selection(a: a, b: b, directions: directions, direction: direction);
  }

  Widget _buildList(List<_Entry> entries, _Selection sel) {
    return ListView(
      key: const ValueKey('members.compare.list'),
      padding: AppSpacing.content,
      children: [
        _InfoNote(
          text:
              '같은 회원의 사진 기록 두 개를 골라주세요. 날짜가 이른 기록이 이전(A)으로 자동 배치돼요. 같은 레슨의 수업 전·후도 비교할 수 있어요.',
        ),
        const SizedBox(height: AppSpacing.sp4),
        if (sel.b != null) ...[
          if (sel.directions.isEmpty)
            _NoCommonDirection(
              a: sel.a!,
              b: sel.b!,
              onReset: () => setState(_picked.clear),
            )
          else
            mark(
              'members.compare.direction.section',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('비교할 방향', style: context.texts.titleMedium),
                  const SizedBox(height: AppSpacing.sp2),
                  DirectionStepper(
                    identifier: 'members.compare.direction',
                    selected: sel.direction,
                    directions: sel.directions,
                    onSelected: (d) => setState(() => _direction = d),
                  ),
                  const SizedBox(height: AppSpacing.sp1),
                  Text(
                    '두 기록에 모두 있는 방향만 보여요.',
                    style: context.texts.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sp4),
        ],
        for (final e in entries)
          _EntryCard(
            entry: e,
            badge: e == sel.a
                ? 'A 이전'
                : e == sel.b
                ? 'B 이후'
                : null,
            direction: sel.direction,
            onTap: () => _toggle(_entryKey(e)),
          ),
      ],
    );
  }

  Widget _buildActions(_Selection sel) {
    final a = sel.a;
    final b = sel.b;
    final direction = sel.direction;
    final ap = (a == null || direction == null)
        ? null
        : photoForDirection(a.photos, direction);
    final bp = (b == null || direction == null)
        ? null
        : photoForDirection(b.photos, direction);
    final valid = ap != null && bp != null && ap.id != bp.id;
    final String? reason = b == null
        ? '비교할 기록 2개를 골라주세요.'
        : (sel.directions.isEmpty ? '같은 방향 사진이 있는 기록을 골라주세요.' : null);
    return BottomActionBar(
      identifier: 'members.compare.actions',
      leading: reason == null
          ? null
          : Text(
              reason,
              key: const ValueKey('members.compare.open.reason'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
      primary: mark(
        'members.compare.open.button',
        FilledButton.icon(
          onPressed: !valid
              ? null
              : () => context.pushNamed(
                  AppRoutes.compareView,
                  queryParameters: {
                    // 비교 화면은 방향이 없으면 선택을 잃은 것으로
                    // 보고 재선택 안내만 띄운다.
                    AppParams.direction: direction!.key,
                    AppParams.beforePhotoId: ap.id,
                    AppParams.afterPhotoId: bp.id,
                  },
                ),
          icon: const Icon(Icons.compare),
          label: const Text('선택한 기록 비교하기'),
        ),
      ),
    );
  }
}

class _Selection {
  final _Entry? a;
  final _Entry? b;
  final List<BodyDirection> directions;
  final BodyDirection? direction;
  const _Selection({
    required this.a,
    required this.b,
    required this.directions,
    required this.direction,
  });
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote({required this.text});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.primaryContainer,
      borderRadius: AppRadius.mdAll,
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sp3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: context.colors.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sp2),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EntryCard extends StatelessWidget {
  final _Entry entry;

  /// 'A 이전' / 'B 이후'. null이면 고르지 않은 기록.
  final String? badge;
  final BodyDirection? direction;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.badge,
    required this.direction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = badge != null;
    final colors = context.colors;
    final thumb =
        (direction == null
            ? null
            : photoForDirection(entry.photos, direction!)) ??
        entry.photos.first;
    final directions = DirectionStepper.standardDirections
        .where((d) => entry.photos.any((p) => p.direction == d))
        .map((d) => d.label)
        .join(' · ');
    final date = lessonDate(entry.record.shotAt);
    final phase = phases[entry.phase] ?? '';
    final id = 'members.compare.${_entryKey(entry)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
      child: Semantics(
        identifier: id,
        button: true,
        selected: selected,
        label: '$date $phase, $directions${selected ? ', $badge' : ''}',
        excludeSemantics: true,
        child: Material(
          key: ValueKey(id),
          color: colors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sp3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumbnail(photo: thumb),
                  const SizedBox(width: AppSpacing.sp3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(date, style: context.numericTexts.labelLarge),
                        const SizedBox(height: AppSpacing.sp1),
                        Wrap(
                          spacing: AppSpacing.sp2,
                          runSpacing: AppSpacing.sp1,
                          children: [
                            StatusPill(label: phase),
                            if (badge != null)
                              StatusPill(
                                label: badge!,
                                tone: StatusPillTone.primary,
                                identifier: '$id.badge',
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sp1),
                        Text(
                          directions,
                          style: context.texts.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sp2),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 원본 비율을 그대로 보여주는 작은 썸네일(잘라내지 않는다).
class _Thumbnail extends StatelessWidget {
  final BodyPhoto photo;
  const _Thumbnail({required this.photo});
  static const _width = 56.0;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: _width,
    height: _width * 4 / 3,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.photoColors.backdrop,
        borderRadius: AppRadius.smAll,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.smAll,
        child: Image.file(
          File(photo.filePath),
          fit: BoxFit.contain,
          // 썸네일 크기로만 디코딩해 긴 목록에서도 가볍게 유지한다.
          cacheWidth: (_width * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => Icon(
            Icons.broken_image_outlined,
            color: context.photoColors.onChrome,
          ),
        ),
      ),
    ),
  );
}

/// 비교할 사진 기록이 두 개보다 적을 때(Stitch 29).
class _NotEnoughRecords extends StatelessWidget {
  final int count;
  const _NotEnoughRecords({required this.count});
  @override
  Widget build(BuildContext context) => mark(
    'members.compare.notEnough',
    Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.sp6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: context.colors.secondaryContainer,
              child: Icon(
                Icons.photo_library_outlined,
                size: 32,
                color: context.colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.sp4),
            Text(
              '비교할 사진 기록이 더 필요해요',
              textAlign: TextAlign.center,
              style: context.texts.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sp2),
            Text(
              '사진이 있는 기록이 두 개 이상 있어야 비교할 수 있어요. 지금은 $count개예요. 일지는 사진 없이도 계속 쓸 수 있어요.',
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 고른 두 기록에 같은 방향 사진이 없을 때(Stitch 30). 어느 기록에 어떤
/// 방향이 있는지 밝히고 다시 고르게 한다.
class _NoCommonDirection extends StatelessWidget {
  final _Entry a;
  final _Entry b;
  final VoidCallback onReset;
  const _NoCommonDirection({
    required this.a,
    required this.b,
    required this.onReset,
  });

  String _line(String tag, _Entry e) {
    final dirs = DirectionStepper.standardDirections
        .where((d) => e.photos.any((p) => p.direction == d))
        .map((d) => d.label)
        .join(', ');
    return '$tag ${lessonDate(e.record.shotAt)} ${phases[e.phase] ?? ''}: $dirs';
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return mark(
      'members.compare.noDirection',
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: semantic.warningFill),
        ),
        child: Padding(
          padding: AppSpacing.content,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: semantic.warning),
                  const SizedBox(width: AppSpacing.sp2),
                  Expanded(
                    child: Text(
                      '두 기록에 같은 방향 사진이 없어요',
                      style: context.texts.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sp2),
              Text(_line('A', a), style: context.texts.bodyMedium),
              Text(_line('B', b), style: context.texts.bodyMedium),
              const SizedBox(height: AppSpacing.sp2),
              mark(
                'members.compare.reset.button',
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('기록 다시 고르기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
